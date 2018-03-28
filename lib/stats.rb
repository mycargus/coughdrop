# https://developers.google.com/maps/documentation/javascript/tutorial
# http://stackoverflow.com/questions/19304574/center-set-zoom-of-map-to-cover-all-markers-visible-markers

module Stats
  def self.cached_daily_use(user_id, options)
    user = User.find_by_global_id(user_id)
    if !user || WeeklyStatsSummary.where(:user_id => user.id).count == 0
      sanitize_find_options!(options, user) if user.eval_account?
      return daily_use(user_id, options)
    end
    sanitize_find_options!(options, user)
    week_start = options[:start_at].utc.beginning_of_week(:sunday)
    week_end = options[:end_at].utc.end_of_week(:sunday)
    start_weekyear = (week_start.to_date.cwyear * 100) + week_start.to_date.cweek
    end_weekyear = (week_end.to_date.cwyear * 100) + week_end.to_date.cweek
    summaries = WeeklyStatsSummary.where(['user_id = ? AND weekyear >= ? AND weekyear <= ?', user.id, start_weekyear, end_weekyear])
    summary_lookups = {}
    summaries.each{|s| summary_lookups[s.weekyear] = s }

    days = {}
    all_stats = []
    options[:start_at].to_date.upto(options[:end_at].to_date) do |date|
      weekyear = (date.beginning_of_week(:sunday).cwyear * 100) + date.beginning_of_week(:sunday).cweek
      summary = summary_lookups[weekyear]
      day = summary && summary.data && summary.data['stats']['days'][date.to_s]
      filtered_day_stats = nil
      if day
        filtered_day_stats = [day['total']]
        if options[:device_ids] || options[:location_ids]
          groups = day['group_counts'].select do |group|
            (!options[:device_ids] || options[:device_ids].include?(group['device_id'])) && 
            (!options[:location_ids] || options[:location_ids].include?(group['geo_cluster_id']) || options[:location_ids].include?(group['ip_cluster_id']))
          end
          filtered_day_stats = groups
        end
      else
        filtered_day_stats = [Stats.stats_counts([])]
      end
      all_stats += filtered_day_stats
      days[date.to_s] = usage_stats(filtered_day_stats)
    end
    
    res = usage_stats(all_stats)
    res[:days] = days
    res[:start_at] = options[:start_at].to_time.utc.iso8601
    res[:end_at] = options[:end_at].to_time.utc.iso8601
    res[:cached] = true
    res
  end
  
  # TODO: this doesn't account for timezones at all. wah waaaaah.
  def self.daily_use(user_id, options)
    sessions = find_sessions(user_id, options)
    
    total_stats = init_stats(sessions)
    total_stats.merge!(time_block_use_for_sessions(sessions))
    days = {}
    options[:start_at].to_date.upto(options[:end_at].to_date) do |date|
      day_sessions = sessions.select{|s| s.started_at.to_date == date }
      day_stats = stats_counts(day_sessions, total_stats)
      day_stats.merge!(time_block_use_for_sessions(day_sessions))
      
      # TODO: cache this day object, maybe in advance
      days[date.to_s] = usage_stats(day_stats)
    end
    res = usage_stats(total_stats)
    
    res.merge!(touch_stats(sessions))
    res.merge!(device_stats(sessions))
    res.merge!(sensor_stats(sessions))
    res.merge!(parts_of_speech_stats(sessions))
    
    res[:days] = days

    res[:locations] = location_use_for_sessions(sessions)
    res[:start_at] = options[:start_at].to_time.utc.iso8601
    res[:end_at] = options[:end_at].to_time.utc.iso8601
    res
    # collect all matching sessions
    # build a stats object based on all sessions including:
    # - total utterances
    # - average words per utterance
    # - average buttons per utterance
    # - total buttons
    # - most popular words
    # - most popular boards
    # - total button presses per day
    # - unique button presses per day
    # - button presses per day per button (top 20? no, because we need this to figure out words they're using more or less than before)
    # - buttons per minute during an active session
    # - utterances per minute (hour?) during an active session
    # - words per minute during an active session
    # TODO: need some kind of baseline to compare against, a milestone model of some sort
    # i.e. someone presses "record baseline" and stats can used the newest baseline before start_at
    # or maybe even baseline_id can be set as a stats option -- ooooooooh...
  end
  
  # TODO: TIMEZONES
  def self.hourly_use(user_id, options)
    sessions = find_sessions(user_id, options)

    total_stats = init_stats(sessions)
    
    hours = []
    24.times do |hour_number|
      hour_sessions = sessions.select{|s| s.started_at.hour == hour_number }
      hour_stats = stats_counts(hour_sessions, total_stats)
      hour = usage_stats(hour_stats)
      hour[:hour] = hour_number
      hour[:locations] = location_use_for_sessions(hour_sessions)
      hours << hour
    end
    
    res = usage_stats(total_stats)
    res[:hours] = hours

    res[:start_at] = options[:start_at].to_time.utc.iso8601
    res[:end_at] = options[:end_at].to_time.utc.iso8601
    res
  end
  
  def self.board_use(board_id, options)
    board = Board.find_by_global_id(board_id)
    if !board
      return {
        :uses => 0,
        :home_uses => 0,
        :stars => 0,
        :forks => 0,
        :popular_forks => []
      }
    end
    res = {}
    # number of people using in their board set
    res[:uses] = board.settings['uses']
    # number of people using as their home board
    res[:home_uses] = board.settings['home_uses']
    # number of stars
    res[:stars] = board.stars
    # number of forks
    res[:forks] = board.settings['forks']
    # popular copies
    boards = Board.where(:parent_board_id => board.id).sort_by{|b| b.settings['popularity'] }.select{|b| b.settings['uses'] > 10 }.reverse[0, 5]
    res[:popular_forks] = boards.map{|b| JsonApi::Board.as_json(b) }
    # TODO: total uses over time
    # TODO: uses of each button over time
    res
  end

  def self.median(list)
    sorted = list.sort
    len = sorted.length
    return (sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0
  end
  
  def self.device_stats(sessions)
    res = []
    sessions.group_by(&:device).each do |device, device_sessions|
      next unless device
      stats = {}
      stats[:id] = device.global_id
      stats[:name] = device.settings['name'] || "Unspecified device"
      stats[:last_used_at] = device.last_used_at.iso8601
      stats[:total_sessions] = device_sessions.select{|s| s.log_type == 'session' }.length
      started = device_sessions.map(&:started_at).compact.min
      stats[:started_at] = started && started.iso8601
      ended = device_sessions.map(&:ended_at).compact.max
      stats[:ended_at] = ended && ended.iso8601

      res << stats
    end
    res = res.sort_by{|r| r[:total_sessions] }.reverse
    {:devices => res}
  end
  
  def self.merge_sensor_stats!(res, stats)
    ['volume', 'ambient_light', 'screen_brightness', 'orientation'].each do |sensor_metric|
      if stats[sensor_metric] && stats[sensor_metric]['total'] > 0
        res[sensor_metric] ||= {}
        res[sensor_metric]['total'] ||= 0
        res[sensor_metric]['average'] ||= 0
        if stats[sensor_metric]['average']
          if res[sensor_metric]['total'] > 0
            res[sensor_metric]['average'] = ((res[sensor_metric]['average'] * res[sensor_metric]['total']) + (stats[sensor_metric]['average'] * stats[sensor_metric]['total'])) / (res[sensor_metric]['total'] + stats[sensor_metric]['total'])
          else
            res[sensor_metric]['average'] = stats[sensor_metric]['average']
          end
          res[sensor_metric]['average'] = res[sensor_metric]['average'].round(2)
        end
        res[sensor_metric]['total'] += stats[sensor_metric]['total']
        if sensor_metric == 'orientation'
          ['alpha', 'beta', 'gamma'].each do |level|
            if stats[sensor_metric][level] && stats[sensor_metric][level]['total'] > 0
              res[sensor_metric][level] ||= {}
              res[sensor_metric][level]['total'] ||= 0
              res[sensor_metric][level]['average'] ||= 0
              if stats[sensor_metric][level]['average']
                if res[sensor_metric][level]['total'] > 0
                  res[sensor_metric][level]['average'] = ((res[sensor_metric][level]['average'] * res[sensor_metric][level]['total']) + (stats[sensor_metric][level]['average'] * stats[sensor_metric][level]['total'])) / (res[sensor_metric][level]['total'] + stats[sensor_metric][level]['total'])
                else
                  res[sensor_metric][level]['average'] = stats[sensor_metric][level]['average']
                end
                res[sensor_metric][level]['average'] = res[sensor_metric][level]['average'].round(2)
              end
              res[sensor_metric][level]['total'] += stats[sensor_metric][level]['total']
              stats[sensor_metric][level]['histogram'].each do |key, cnt|
                res[sensor_metric][level]['histogram'] ||= {}
                res[sensor_metric][level]['histogram'][key] ||= 0
                res[sensor_metric][level]['histogram'][key] += cnt
              end
            end
          end
          if stats[sensor_metric]['layout'] && stats[sensor_metric]['layout']['total'] > 0
            res[sensor_metric]['layout'] ||= {}
            stats[sensor_metric]['layout'].each do |key, cnt|
              res[sensor_metric]['layout'][key] ||= 0
              res[sensor_metric]['layout'][key] += cnt
            end
          end
        else
          stats[sensor_metric]['histogram'].each do |key, cnt|
            res[sensor_metric]['histogram'] ||= {}
            res[sensor_metric]['histogram'][key] ||= 0
            res[sensor_metric]['histogram'][key] += cnt
          end
        end
      end
    end
  end
  
  def self.sensor_stats(sessions)
    res = {}
    sessions.each do |session|
      merge_sensor_stats!(res, session.data['stats'])
    end
    res
  end
  
  def self.touch_stats(sessions)
    counts = {}
    max = 0
    sessions.each do |session|
      (session.data['touch_locations'] || {}).each do |board_id, xs|
        xs.each do |x, ys|
          ys.each do |y, count|
            counts[x.to_s + "," + y.to_s] ||= 0
            counts[x.to_s + "," + y.to_s] += count
            max = [max, counts[x.to_s + "," + y.to_s]].max
          end
        end
      end
    end
    {:touch_locations => counts, :max_touches => max}
  end

  def self.usage_stats(stats_list)
    return unless stats_list
    stats_list = [stats_list] if !stats_list.is_a?(Array)
    
    res = {
      :total_sessions => 0,
      :total_utterances => 0,
      :words_per_utterance => 0.0,
      :buttons_per_utterance => 0.0,
      :total_buttons => 0,
      :unique_buttons => 0,
      :modeled_buttons => 0,
      :total_words => 0,
      :unique_words => 0,
      :modeled_words => 0,
      :words_by_frequency => [],
      :buttons_by_frequency => [],
      :modeled_words_by_frequency => [],
      :modeled_buttons_by_frequency => [],
#      :word_sequences => [],
      :words_per_minute => 0.0,
      :buttons_per_minute => 0.0,
      :utterances_per_minute => 0.0,
      :goals => []
    }
    
    total_utterance_words = 0
    total_utterance_buttons = 0
    total_utterances = 0
    total_session_seconds = 0
    total_words = 0
    total_buttons = 0
    all_button_counts = {}
#    all_word_sequences = []
    all_word_counts = {}
    modeled_button_counts = {}
    modeled_word_counts = {}
    all_devices = nil
    all_locations = nil
    goals = {}
    button_chains = {}

    stats_list.each do |stats|
      stats = stats.with_indifferent_access
      # TODO: should we be calculating EVERYTHING off of only uttered content?
      buttons = stats[:all_button_counts].map{|k, v| v['count'] }.sum
      words = stats[:all_word_counts].map{|k, v| v }.sum
      total_buttons += buttons
      total_words += words
      total_utterance_words += stats[:total_utterance_words] if stats[:total_utterance_words]
      total_utterance_buttons += stats[:total_utterance_buttons] if stats[:total_utterance_buttons]
      total_utterances += stats[:total_utterances] if stats[:total_utterances]
      total_session_seconds += stats[:total_session_seconds] if stats[:total_session_seconds]
      
      res[:total_sessions] += stats[:total_sessions]
      res[:total_utterances] += stats[:total_utterances]
      res[:total_buttons] += buttons
      res[:modeled_buttons] += (stats[:modeled_button_counts] || {}).map{|k, v| v['count'] }.sum
      res[:unique_buttons] += stats[:all_button_counts].keys.length
      res[:total_words] += words
      res[:modeled_words] += (stats[:modeled_word_counts] || {}).map{|k, v| v }.sum
      res[:unique_words] += stats[:all_word_counts].keys.length
      res[:started_at] = [res[:started_at], stats[:started_at]].compact.min
      res[:ended_at] = [res[:ended_at], stats[:ended_at]].compact.max
      stats[:all_button_counts].each do |ref, button|
        if all_button_counts[ref]
          all_button_counts[ref]['count'] += button['count']
        else
          all_button_counts[ref] = button.merge({})
        end
      end
      stats[:all_word_counts].each do |word, cnt|
        all_word_counts[word] ||= 0
        all_word_counts[word] += cnt
      end
      (stats[:modeled_button_counts] || {}).each do |ref, button|
        if modeled_button_counts[ref]
          modeled_button_counts[ref]['count'] += button['count']
        else
          modeled_button_counts[ref] = button.merge({})
        end
      end
      (stats[:modeled_word_counts] || {}).each do |word, cnt|
        modeled_word_counts[word] ||= 0
        modeled_word_counts[word] += cnt
      end
      if stats[:all_word_sequence]
#        all_word_sequences << stats[:all_word_sequence].join(' ')
      end
      
      if stats[:buttons_used]
        stats[:buttons_used]['button_chains'].each do |chain, count|
          button_chains[chain] = (button_chains[chain] || 0) + count
        end
      end
      
      merge_sensor_stats!(res, stats)

      [:touch_locations, :parts_of_speech, :core_words, :modeled_parts_of_speech, :modeled_core_words, :parts_of_speech_combinations].each do |metric|
        if stats[metric]
          res[metric] ||= {}
          stats[metric].each do |key, cnt|
            res[metric][key] ||= 0
            res[metric][key] += cnt
          end
        end
      end
      
      if stats[:timed_blocks]
        offset_blocks = time_offset_blocks(stats[:timed_blocks])
        res[:time_offset_blocks] ||= {}
        offset_blocks.each do |block, cnt|
          res[:time_offset_blocks][block] ||= 0
          res[:time_offset_blocks][block] += cnt
        end
      end
      if stats[:modeled_timed_blocks]
        offset_blocks = time_offset_blocks(stats[:modeled_timed_blocks])
        res[:modeled_time_offset_blocks] ||= {}
        offset_blocks.each do |block, cnt|
          res[:modeled_time_offset_blocks][block] ||= 0
          res[:modeled_time_offset_blocks][block] += cnt
        end
      end

      if stats[:devices]
        all_devices ||= {}
        stats[:devices].each do |device|
          if all_devices[device['id']]
            all_devices[device['id']]['total_sessions'] += device['total_sessions']
            all_devices[device['id']]['started_at'] = [all_devices[device['id']]['started_at'], device['started_at']].compact.min
            all_devices[device['id']]['ended_at'] = [all_devices[device['id']]['ended_at'], device['ended_at']].compact.max
          else
            all_devices[device['id']] = device.merge({})
          end
        end
      end
      if stats[:locations]
        all_locations ||= {}
        stats[:locations].each do |location|
          if all_locations[location['id']]
            all_locations[location['id']]['total_sessions'] += location['total_sessions']
            all_locations[location['id']]['started_at'] = [all_locations[location['id']]['started_at'], location['started_at']].compact.min
            all_locations[location['id']]['ended_at'] = [all_locations[location['id']]['ended_at'], location['ended_at']].compact.max
          else
            all_locations[location['id']] = location.merge({})
          end
        end
      end
      if stats[:goals]
        stats[:goals].each do |id, goal|
          goals[id] ||= {
            'id' => goal['id'],
            'summary' => goal['summary'],
            'positives' => 0,
            'negatives' => 0,
            'statuses' => []
          }
          goals[id]['positives'] += goal['positives']
          goals[id]['negatives'] += goal['negatives']
          goals[id]['statuses'] += goal['statuses']
        end
      end
    end
    goals.each do |id, goal|
      res[:goals] << goal
    end
    if all_devices
      res[:devices] = all_devices.map(&:last)
    end
    if all_locations
      res[:locations] = all_locations.map(&:last)
    end
    if res[:touch_locations]
      res[:max_touches] = res[:touch_locations].map(&:last).max
    end
    res[:button_chains] = {}
    button_chains.each do |chain, count|
      res[:button_chains][chain] = count if count > (res[:total_sessions] / 25)
    end
    if res[:time_offset_blocks]
      max = 0
      combined_max = 0
      res[:time_offset_blocks].each do |idx, val|
        sum = val + [res[:time_offset_blocks][idx - 1] || 0, res[:time_offset_blocks][idx + 1] || 0].max
        max = val if val > max
        combined_max = sum if sum > combined_max
      end
      res[:max_time_block] = max
      res[:max_combined_time_block] = combined_max
    end
    if res[:modeled_time_offset_blocks]
      max = 0
      combined_max = 0
      res[:modeled_time_offset_blocks].each do |idx, val|
        sum = val + [res[:modeled_time_offset_blocks][idx - 1] || 0, res[:modeled_time_offset_blocks][idx + 1] || 0].max
        max = val if val > max
        combined_max = sum if sum > combined_max
      end
      res[:max_modeled_time_block] = max
      res[:max_combined_modeled_time_block] = combined_max
    end
    res[:words_per_utterance] += total_utterances > 0 ? (total_utterance_words / total_utterances) : 0.0
    res[:buttons_per_utterance] += total_utterances > 0 ? (total_utterance_buttons / total_utterances) : 0.0
    res[:words_per_minute] += total_session_seconds > 0 ? (total_words / total_session_seconds * 60) : 0.0
    res[:buttons_per_minute] += total_session_seconds > 0 ? (total_buttons / total_session_seconds * 60) : 0.0
    res[:utterances_per_minute] +=  total_session_seconds > 0 ? (total_utterances / total_session_seconds * 60) : 0.0
    res[:buttons_by_frequency] = all_button_counts.to_a.sort_by{|ref, button| [button['count'], button['text']] }.reverse.map(&:last)[0, 50]
    res[:words_by_frequency] = all_word_counts.to_a.sort_by{|word, cnt| [cnt, word] }.reverse.map{|word, cnt| {'text' => word, 'count' => cnt} }[0, 100]
    res[:modeled_buttons_by_frequency] = modeled_button_counts.to_a.sort_by{|ref, button| [button['count'], button['text']] }.reverse.map(&:last)[0, 50]
    res[:modeled_words_by_frequency] = modeled_word_counts.to_a.sort_by{|word, cnt| [cnt, word] }.reverse.map{|word, cnt| {'text' => word, 'count' => cnt} }[0, 100]
    # res[:word_sequences] = all_word_sequences
    res
  end
  
  DEVICE_PREFERENCES = [:access_method, :voice_uri, :text_position, :auto_home_return, :vocalization_height, :system, :browser, :window_width, :window_height]
  
  def self.stats_counts(sessions, total_stats_list=nil)
    stats = init_stats(sessions)
    device_prefs = DEVICE_PREFERENCES
    sessions.each do |session|
      if session.data['stats']
        # TODO: more filtering needed for board-specific drill-down
        stats[:total_session_seconds] += session.data['stats']['session_seconds'] || 0
        stats[:total_utterances] += session.data['stats']['utterances'] || 0
        stats[:total_utterance_words] += session.data['stats']['utterance_words'] || 0
        stats[:total_utterance_buttons] += session.data['stats']['utterance_buttons'] || 0
        (session.data['stats']['all_button_counts'] || []).each do |ref, button|
          if stats[:all_button_counts][ref]
            stats[:all_button_counts][ref]['count'] += button['count']
          else
            stats[:all_button_counts][ref] = button.merge({})
          end
        end
        (session.data['stats']['all_word_counts'] || []).each do |word, cnt|
          stats[:all_word_counts][word] ||= 0
          stats[:all_word_counts][word] += cnt
        end
        stats[:all_word_sequences] << session.data['stats']['all_word_sequence'] || []
        (session.data['stats']['modeled_button_counts'] || []).each do |ref, button|
          if stats[:modeled_button_counts][ref]
            stats[:modeled_button_counts][ref]['count'] += button['count']
          else
            stats[:modeled_button_counts][ref] = button.merge({})
          end
        end
        (session.data['stats']['modeled_word_counts'] || []).each do |word, cnt|
          stats[:modeled_word_counts][word] ||= 0
          stats[:modeled_word_counts][word] += cnt
        end
        if session.data['goal']
          goal = session.data['goal']
          stats[:goals] ||= {}
          stats[:goals][goal['id']] ||= {
            'id' => goal['id'],
            'summary' => goal['summary'],
            'positives' => 0,
            'negatives' => 0,
            'statuses' => []
          }
          stats[:goals][goal['id']]['positives'] += goal['positives'] if goal['positives']
          stats[:goals][goal['id']]['negatives'] += goal['negatives'] if goal['negatives']
          stats[:goals][goal['id']]['statuses'] << goal['status'] if goal['status']
        end
        
        device_prefs.each do |key|
          val = session.data['stats'][key]
          if key && val != nil
            stats[:device]["#{key}s".to_sym][val] ||= 0
            stats[:device]["#{key}s".to_sym][val] += 1
          end
        end
      end
    end
    starts = sessions.map(&:started_at).compact.sort
    ends = sessions.map(&:ended_at).compact.sort
    stats[:started_at] = starts.length > 0 ? starts.first.utc.iso8601 : nil
    stats[:ended_at] = ends.length > 0 ? ends.last.utc.iso8601 : nil
    if total_stats_list
      total_stats_list = [total_stats_list] unless total_stats_list.is_a?(Array)
      total_stats_list.each do |total_stats|
        total_stats[:total_utterances] += stats[:total_utterances]
        total_stats[:total_utterance_words] += stats[:total_utterance_words]
        total_stats[:total_utterance_buttons] += stats[:total_utterance_buttons]
        total_stats[:total_session_seconds] += stats[:total_session_seconds]
        stats[:all_button_counts].each do |ref, button|
          if total_stats[:all_button_counts][ref]
            total_stats[:all_button_counts][ref]['count'] += button['count']
          else
            total_stats[:all_button_counts][ref] = button.merge({})
          end
        end
        stats[:all_word_counts].each do |word, cnt|
          total_stats[:all_word_counts][word] ||= 0
          total_stats[:all_word_counts][word] += cnt
        end
        total_stats[:all_word_sequences] += stats[:all_word_sequences]
        stats[:modeled_button_counts].each do |ref, button|
          if total_stats[:modeled_button_counts][ref]
            total_stats[:modeled_button_counts][ref]['count'] += button['count']
          else
            total_stats[:modeled_button_counts][ref] = button.merge({})
          end
        end
        stats[:modeled_word_counts].each do |word, cnt|
          total_stats[:modeled_word_counts][word] ||= 0
          total_stats[:modeled_word_counts][word] += cnt
        end
        (stats[:goals] || {}).each do |id, goal|
          total_stats[:goals] ||= {}
          total_stats[:goals][id] ||= {
            'id' => goal['id'],
            'summary' => goal['summary'],
            'positives' => 0,
            'negatives' => 0,
            'statuses' => []
          }
          total_stats[:goals][id]['positives'] += goal['positives']
          total_stats[:goals][id]['negatives'] += goal['negatives']
          total_stats[:goals][id]['statuses'] += goal['statuses']
        end
        device_prefs.each do |pref|
          (stats[:device]["#{pref}s".to_sym] || {}).each do |key, val|
            total_stats[:device]["#{pref}s".to_sym][key] ||= 0
            total_stats[:device]["#{pref}s".to_sym][key] += val
          end
        end
        total_stats[:started_at] = [total_stats[:started_at], stats[:started_at]].compact.sort.first
        total_stats[:ended_at] = [total_stats[:ended_at], stats[:ended_at]].compact.sort.last
      end
    end
    stats
  end
  
  def self.init_stats(sessions)
    stats = {}
    stats[:total_sessions] = sessions.select{|s| s.log_type == 'session' }.length
    stats[:total_utterances] = 0.0
    stats[:total_utterance_words] = 0.0
    stats[:total_utterance_buttons] = 0.0
    stats[:total_session_seconds] = 0.0
    stats[:all_button_counts] = {}
    stats[:all_word_counts] = {}
    stats[:all_word_sequences] = []
    stats[:modeled_button_counts] = {}
    stats[:modeled_word_counts] = {}
    stats[:device] = {
      :acces_methods => {},
      :voice_uris => {},
      :text_positions => {},
      :auto_home_returns => {},
      :vocalization_heights => {},
      :systems => {},
      :browsers => {},
      :window_widths => {},
      :window_heights => {}
    }
    
    stats
  end
  
  def self.sanitize_find_options!(options, user=nil)
    if options[:snapshot_id] && user
      snapshot = LogSnapshot.find_by_global_id(options[:snapshot_id])
      if snapshot && snapshot.user == user
        options[:start] = snapshot.settings['start']
        options[:end] = snapshot.settings['end']
        options[:device_id] = snapshot.settings['device_id']
        options[:location_id] = snapshot.settings['location_id']
      end
    end
    options[:end_at] = options[:end_at] || (Date.parse(options[:end]) rescue nil)
    options[:start_at] = options[:start_at] || (Date.parse(options[:start]) rescue nil)
    options[:end_at] ||= Time.now + 1000
    end_time = (options[:end_at].to_date + 1).to_time
    options[:end_at] = (end_time + end_time.utc_offset - 1).utc
    options[:start_at] ||= (options[:end_at]).to_date << 2 # limit by date range
    # eval accounts are limited to 60-day windows
    if user && user.eval_account?
      options[:start_at] = [options[:start_at], 60.days.ago].max
      options[:end_at] = [options[:end_at], 60.days.ago, options[:start_at] + 7.days].max
    end
    options[:start_at] = options[:start_at].to_time.utc
    if options[:end_at].to_time - options[:start_at].to_time > 6.months.to_i
      raise(StatsError, "time window cannot be greater than 6 months")
    end
    options[:device_ids] = [options[:device_id]] if !options[:device_id].blank? # limit to a list of devices
    options[:device_ids] = nil if options[:device_ids].blank?
    options[:board_ids] = [options[:board_id]] if !options[:board_id].blank? # limit to a single board (this is not board-level stats, this is user-level drill-down)
    options[:board_ids] = nil if options[:device_ids].blank?
    options[:location_ids] = [options[:location_id]] if !options[:location_id].blank? # limit to a single geolocation or ip address
    options[:location_ids] = nil if options[:location_ids].blank?
  end
  
  def self.find_sessions(user_id, options)
    sanitize_find_options!(options)
    user = user_id && User.find_by_global_id(user_id)
    raise(StatsError, "user not found") unless user || user_id == 'all'
    sessions = LogSession.where(['started_at > ? AND ended_at < ?', options[:start_at], options[:end_at]])
    sessions = sessions.where({'user_id' => user.id}) unless user_id == 'all'
    if options[:device_ids]
      devices = Device.find_all_by_global_id(options[:device_ids]).select{|d| d.user_id == user.id }
      sessions = sessions.where(:device_id => devices.map(&:id))
    end
    if options[:location_ids]
      # TODO: supporting multiple locations is slightly trickier than multiple devices
      cluster = ClusterLocation.find_by_global_id(options[:location_ids][0])
      raise(StatsError, "cluster not found") unless cluster && cluster.user_id == user.id
      if cluster.ip_address?
        sessions = sessions.where(:ip_cluster_id => cluster.id)
      elsif cluster.geo?
        sessions = sessions.where(:geo_cluster_id => cluster.id)
      else
        raise(StatsError, "this should never be reached")
      end
    end
    if options[:board_ids]
      sessions = sessions.select{|s| s.has_event_for_board?(options[:board_id]) }
    end
    sessions
  end
  
  def self.location_use_for_sessions(sessions)
    geo_ids = sessions.select{|s| s.geo_cluster_id && s.geo_cluster_id != -1 }.map(&:geo_cluster_id).compact.uniq
    ip_ids = sessions.select{|s| s.ip_cluster_id && s.ip_cluster_id != -1 }.map(&:ip_cluster_id).compact.uniq
    res = []
    return res unless geo_ids.length > 0 || ip_ids.length > 0
    ClusterLocation.where(:id => (geo_ids + ip_ids)).each do |cluster|
      cluster_sessions = sessions.select{|s| s.ip_cluster_id == cluster.id || s.geo_cluster_id == cluster.id }

      location = {}
      location[:id] = cluster.global_id
      location[:type] = cluster.cluster_type
      location[:total_sessions] = cluster_sessions.select{|s| s.log_type == 'session' }.length
      started = cluster_sessions.map(&:started_at).compact.min
      location[:started_at] = started && started.iso8601
      ended = cluster_sessions.map(&:ended_at).compact.max
      location[:ended_at] = ended && ended.iso8601

      if cluster.ip_address?
        location[:readable_ip_address] = cluster.data['readable_ip_address']
        location[:ip_address] = cluster.data['ip_address']
      end
      if cluster.geo? && cluster.data && cluster.data['geo']
        location[:geo] = {
          :latitude => cluster.data['geo'][0],
          :longitude => cluster.data['geo'][1],
          :altitude => cluster.data['geo'][2]
        }
      end
      res << location
    end
    res
  end

  def self.goals_for_user(user, start_at, end_at)
    goals = UserGoal.where(user_id: user.id)
    goals = goals.select{|g| g.active_during(start_at, end_at) }
    res = {
      'goals_set' => {},
      'badges_earned' => {}
    }
    templates = UserGoal.find_all_by_global_id(goals.map{|g| g.settings['template_id'] }.compact)
    goals.each do |goal|
      template_goal = templates.detect{|g| g.global_id == goal.settings['template_id'] }
      res['goals_set'][goal.global_id] = {
        'template_goal_id' => goal.settings['template_id'],
        'name' => (template_goal || goal).settings['summary'],
      }
    end
    badges = UserBadge.where(user_id: user.id, earned: true)
    badges = badges.select{|b| b.earned_during(start_at, end_at) }
    badges.each do |badge|
      template = badge.template_goal
      template_badge = template && template.badge_level(badge.level) 
      badge_data = (template_badge || badge.data)
      res['badges_earned'][badge.global_id] = {
        'goal_id' => badge.related_global_id(badge.user_goal_id),
        'template_goal_id' => template && template.global_id,
        'level' => badge.level,
        'global' => badge.data['global_goal'],
        'shared' => badge.highlighted,
        'name' => badge_data['name'] || badge.data['name'],
        'image_url' => badge_data['image_url'] || badge.data['image_url']
      }
    end
    res
  end 
  
  
  def self.buttons_used(sessions)
    res = {
      'button_ids' => [],
      'button_chains' => {}
    }
    sessions.each do |session|
      current_chain = []
      last_timestamp = nil
      last_button_id = nil
      session.data['events'].each do |event|
        if event['type'] == 'button'
          button = event['button']
          if !event['modeling'] && button
            button_text = LogSession.event_text(event)

            if button_text && button_text.length > 0 && (event['button']['spoken'] || event['button']['for_speaking'])
              button_key = "#{button['board']['id']}:#{button['button_id']}"
              res['button_ids'] << button_key
              
              # If less than 2 minutes since the last hit, let's add it to the button sequence,
              # and we'll go ahead and stop counting if it's the same button multiple times
              if (!last_button_id || last_button_id != button_key) && (!last_timestamp || (event['timestamp'] - last_timestamp) < (2 * 60))
                current_chain << button_text
                if current_chain.length >= 3
                  sequence = current_chain[-3, 3]
                  sequence_key = sequence.join(', ')
                  res['button_chains'][sequence_key] = (res['button_chains'][sequence_key] || 0) + 1
                  if current_chain.length >= 4
                    sequence = current_chain[-4, 4]
                    sequence_key = sequence.join(', ')
                    res['button_chains'][sequence_key] = (res['button_chains'][sequence_key] || 0) + 1
                  end
                end
              end
              last_timestamp = event['timestamp']
              last_button_id = button_key
            end
          else
            last_timestamp = nil
            last_button_id = nil
            current_chain = []
          end
        elsif event['type'] == 'utterance' || (event['type'] == 'action' && event['action']['action'] == 'clear')
          last_timestamp = nil
          last_button_id = nil
          current_chain = []
        end
      end
    end
    res
  end 
  
  def self.parts_of_speech_stats(sessions)
    res = {
      :parts_of_speech => {},
      :modeled_parts_of_speech => {},
      :core_words => {},
      :modeled_core_words => {}
    }
    parts = {}
    modeled_parts = {}
    core_words = {}
    modeled_core_words = {}
    sequences = {}
    sessions.each do |session|
      ['parts_of_speech', 'core_words', 'modeled_parts_of_speech', 'modeled_core_words'].each do |key|
        (session.data['stats'][key] || {}).each do |part, cnt|
          res[key.to_sym][part] ||= 0
          res[key.to_sym][part] += cnt
        end
      end
      
      prior_parts = []
      session.data['events'].each do |event|
        if event['type'] == 'action' && event['action'] == 'clear'
          prior_parts = []
        elsif event['type'] == 'utterance'
          prior_parts = []
        elsif event['modified_by_next']
        else
          if event['parts_of_speech'] && event['parts_of_speech']['types']
            current_part = event['parts_of_speech']
            if prior_parts[-1] && prior_parts[-1]['types'] && prior_parts[-2] && prior_parts[-2]['types']
              from_from = prior_parts[-2]['types'][0]
              from = prior_parts[-1]['types'][0]
              to = current_part['types'][0]
              sequences[from_from + "," + from + "," + to] ||= 0
              sequences[from_from + "," + from + "," + to] += 1
              sequences[from_from + "," + from] -= 1 if sequences[from_from + "," + from]
              sequences.delete(from_from + "," + from) if sequences[from_from + "," + from] == 0
              sequences[from + "," + to] ||= 0
              sequences[from + "," + to] += 1
            elsif prior_parts[-1] && prior_parts[-1]['types']
              from = prior_parts[-1]['types'][0]
              to = current_part['types'][0]
              sequences[from + "," + to] ||= 0
              sequences[from + "," + to] += 1
            end
          end
          prior_parts << event['parts_of_speech']
        end
      end
    end
    res[:parts_of_speech_combinations] = sequences
    res
  end
  
  def self.word_pairs(sessions)
    valid_words = WordData.standardized_words
    pairs = {}
    sessions.each do |session|
      last_button_event = nil
      session.data['events'].each do |event|
        if event['type'] == 'button'
          text = LogSession.event_text(event)
          if text && text.length > 0 && (event['button']['spoken'] || event['button']['for_speaking'])
            if last_button_event
              last_text = LogSession.event_text(last_button_event)
              if valid_words[text.downcase] && last_text && valid_words[last_text.downcase]
                if (event['timestamp'] || 0) - (last_button_event['timestamp'] || 0) < 5.minutes.to_i
                  hash = Digest::MD5.hexdigest(text + "::" + last_text)
                  pairs[hash] ||= {
                    'a' => last_text.downcase,
                    'b' => text.downcase,
                    'count' => 0
                  }
                  pairs[hash]['count'] += 1
                end
              end
            end
            last_button_event = event
          end
        end
      end
    end
    pairs
  end
  
  TIMEBLOCK_MOD = 7 * 24 * 4
  TIMEBLOCK_OFFSET = 4 * 24 * 4
  def self.time_block(timestamp)
    ((timestamp.to_i / 60 / 15) + TIMEBLOCK_OFFSET) % TIMEBLOCK_MOD
  end
  
  def self.time_offset_blocks(timed_blocks)
    blocks = {}
    timed_blocks.each do |blockstamp, cnt|
      block = time_block(blockstamp.to_i * 15)
      blocks[block] ||= 0
      blocks[block] += cnt
    end
    max = blocks.map(&:last).max
    blocks
  end
  
  def self.time_block_use_for_sessions(sessions)
    timed_blocks = {}
    modeled_timed_blocks = {}
    sessions.each do |session|
      (session.data['events'] || []).each do |event|
        next unless event['timestamp']
        timed_block = event['timestamp'].to_i / 15
        if event['modeling']
          modeled_timed_blocks[timed_block] ||= 0
          modeled_timed_blocks[timed_block] += 1
        else
          timed_blocks[timed_block] ||= 0
          timed_blocks[timed_block] += 1
        end
      end
    end
    {:timed_blocks => timed_blocks, :max_time_block => timed_blocks.map(&:last).max, :modeled_timed_blocks => modeled_timed_blocks, :max_modeled_timed_block => modeled_timed_blocks.map(&:last).max }
  end

  # TODO: someday start figuring out word complexity and word type for buttons and utterances
  # i.e. how many syllables, applied tenses/modifiers, nouns/verbs/adjectives/etc.
  
  
  def self.lam(sessions)
    res = lam_header
    sessions.each do |session|
      res += lam_entries(session)
    end
    res
  end
  
  def self.lam_header
    lines = []
    lines << "### CAUTION ###"
    lines << "The following data represents an individual's communication"
    lines << "and should be treated accordingly."
    lines << ""
    lines << "LAM Content generated by CoughDrop AAC app"
    lines << "LAM Version 2.00 07/26/01"
    lines << ""
    lines << ""
    lines.join("\n")
  end
  
  def self.process_lam(str, user)
    lines = str.split(/\n/)
    date = Date.today
    events = []
    lines.each do |line|
      line = line.strip
      parts = line.split(/\s+/, 3)
      time = parts[0]
      action = parts[1]
      data = parts[2]
      text_match = data && data.match(/^\"(.+)\"$/)
      text = text_match && text_match[1]
      time_parts = time && time.split(/\:/)
      ts = date.to_time.to_i
      if time_parts && time_parts.length >= 3
        hr, min, sec = time_parts.map(&:to_i)
        ts = date.to_time.change(:hour => hr, :min => min, :sec => sec).to_i
      end
      if action == 'CTL'
        match = data && data.match(/\*\[YY-MM-DD=(.+)\]\*/)
        date_string = match && match[1]
        if date_string
          date = Date.parse(date_string)
        end
      elsif action == 'SPE'
        if ts && text
          events << {
            'type' => 'button',
            'timestamp' => ts,
            'user_id' => user.global_id,
            'button' => {
              'vocalization' => text,
              'type' => 'speak',
              'label' => text,
              'spoken' => true
            }
          }
        end
      elsif action == 'SMP'
        if ts && text
          events << {
            'type' => 'button',
            'timestamp' => ts,
            'user_id' => user.global_id,
            'button' => {
              'type' => 'speak',
              'label' => text,
              'spoken' => true
            }
          
          }
        end
      elsif action == 'WPR'
        if ts && text
          events << {
            'type' => 'button',
            'timestamp' => ts,
            'user_id' => user.global_id,
            'button' => {
              'completion' => text,
              'type' => 'speak',
              'label' => text,
              'spoken' => true
            }
          }
        end
      end
    end
    events
  end

  def self.lam_entries(session)
    lines = []
    date = nil
    (session.data['events'] || []).each do |event|
      # TODO: timezones
      time = Time.at(event['timestamp'])
      stamp = time.strftime("%H:%M:%S")
      if !date || time.to_date != date
        date = time.to_date
        date_stamp = date.strftime('%y-%m-%d')
        lines << "#{stamp} CTL *[YY-MM-DD=#{date_stamp}]*"
      end
      if event['button']
        if event['button']['completion']
          lines << "#{stamp} WPR \"#{event['button']['completion']}\""
        elsif event['button']['vocalization'] && event['button']['vocalization'].match(/^\+/)
          lines << "#{stamp} SPE \"#{event['button']['vocalization'][1..-1]}\""
        elsif event['button']['label'] && (!event['button']['vocalization'] || !event['button']['vocalization'].match(/^:/))
          # TODO: need to confirm, but it seems like if the user got to the word from a 
          # link, that would be qualify as semantic compaction instead of
          # a single-meaning picture...
          lines << "#{stamp} SMP \"#{event['button']['label']}\""
        end
      end
    end
    lines.join("\n") + "\n"
  end
  
  def self.recently_used_boards
    sessions = LogSession.where(:log_type => 'session').where(['started_at > ?', 3.months.ago]); 12
    keys = {}
    idx = 0
    sessions.find_in_batches(:batch_size => 10) do |batch|
      idx += 1
      batch.each do |log|
        (log.data['events'] || []).each do |event|
          if event['type'] == 'button' && event['button'] && event['button']['board']
            key = event['button']['board']['key']
            keys[key] = (keys[key] || 0) + 1
          end
        end
      end
    end
    keys
  end
  
  def self.totals(date)
    date = Date.parse(date) if date.is_a?(String)
    date ||= Date.today
    res = {}
    puts "querying..."
    res[:users] = User.where(['created_at < ?', date]).count
    puts "users: #{res[:users]}"
    res[:boards] = Board.where(['created_at < ?', date]).count
    puts "boards: #{res[:boards]}"
    res[:logs] = LogSession.where(:log_type => 'session').where(['created_at < ?', date]).count
    puts "logs: #{res[:logs]}"
    seconds = LogSession.where(:log_type => 'session').where(['started_at > ? AND started_at < ?', date - 30.days, date]).sum('EXTRACT(epoch FROM (ended_at - started_at))')
    res[:hours] = (seconds / 3600.0).round(2)
    res[:hours_users] = LogSession.where(:log_type => 'session').where(['started_at > ? AND started_at < ?', date - 30.days, date]).distinct.count('user_id')
    puts "log hours: #{res[:hours]} for #{res[:hours_users]} users"
    res[:premium_users] = User.where(['created_at < ?', date]).where(:possibly_full_premium => true).select(&:full_premium?).count
    puts "premium_users: #{res[:premium_users]}"
    res[:communicators] = 0
    User.where(['created_at < ?', date]).find_in_batches(:batch_size => 100).each do |batch|
      res[:communicators] += batch.select(&:communicator_role?).count
    end
    puts "communicators: #{res[:communicators]}"
    maps = {:android => [], :ios => [], :windows => [], :browser => []}
    Device.where(['created_at < ?', date]).find_in_batches(:batch_size => 100).each do |batch|
      batch.each do |device|
        agent = device.settings['user_agent'] || ''
        if agent.match(/android/i) && agent.match(/chrome/i)
          maps[:android] << device.user_id
          maps[:android].uniq!
        elsif agent.match(/ios|iphone|ipad|ipod/i)
          maps[:ios] << device.user_id
          maps[:ios].uniq!
        elsif agent.match(/coughdrop/i) && agent.match(/desktop/i)
          maps[:windows] << device.user_id
          maps[:windows].uniq!
        elsif agent.match(/mozilla/i)
          maps[:browser] << device.user_id
          maps[:browser].uniq!
        end
      end
    end
    maps.each do |key, list|
      res["#{key}_users"] = list.length
      puts "#{key} users: #{list.length}"
    end
    res
  end
  
  class StatsError < StandardError; end
end 