class WeeklyStatsSummary < ActiveRecord::Base
  include SecureSerialize
  include GlobalId
  include Async
  replicated_model  
  
  secure_serialize :data  
  before_save :generate_defaults  
  after_save :schedule_badge_check
  after_save :track_for_trends
  
  def schedule_badge_check
    UserBadge.schedule_once(:check_for, self.related_global_id(self.user_id), self.global_id) if self.user_id && self.user_id > 0
    true
  end
  
  def generate_defaults
    self.data ||= {}
    found_ids = [self.user_id, self.board_id].compact.length
    raise "no summary index defined" if found_ids == 0
    true
  end

  def self.update_for(log_session_id)
    all = false
    log_session = LogSession.find_by_global_id(log_session_id)
    return if !log_session || log_session.log_type != 'session'
    return unless log_session.user_id && log_session.started_at && log_session.data && log_session.data['stats']
    # TODO: if log_session.started_at ever gets updated in a way that changes cweek then
    # multiple weeks need to be updated 
    start_at = log_session.started_at.utc.beginning_of_week(:sunday)
    end_at = log_session.started_at.utc.end_of_week(:sunday)
    cweek = start_at.to_date.cweek
    cwyear = start_at.to_date.cwyear
    weekyear = (cwyear * 100) + cweek

    summary = WeeklyStatsSummary.find_or_create_by(:weekyear => weekyear, :user_id => (all ? 0 : log_session.user_id))
    sessions = Stats.find_sessions((all ? 'all' : log_session.user.global_id), {:start_at => start_at, :end_at => end_at})
    
    total_stats = Stats.init_stats(sessions)
    days = {}
    start_at.to_date.upto(end_at.to_date) do |date|
      day_sessions = sessions.select{|s| s.started_at.to_date == date }
      day_stats = Stats.init_stats(day_sessions)
      groups = []
      
      day_sessions.group_by{|s| [s.geo_cluster_global_id, s.ip_cluster_global_id, s.device_global_id] }.each do |ids, group_sessions|
        geo_cluster_id, ip_cluster_id, device_id = ids
        group_stats = Stats.stats_counts(group_sessions, [day_stats, total_stats])
        group_stats['geo_cluster_id'] = geo_cluster_id
        group_stats['ip_cluster_id'] = ip_cluster_id
        group_stats['device_id'] = device_id
        
        group_stats.merge!(Stats.touch_stats(group_sessions))
        group_stats.merge!(Stats.device_stats(group_sessions))
        group_stats.merge!(Stats.sensor_stats(group_sessions))
        group_stats.merge!(Stats.time_block_use_for_sessions(group_sessions))
        group_stats.merge!(Stats.parts_of_speech_stats(group_sessions))
        group_stats[:locations] = Stats.location_use_for_sessions(group_sessions)
        groups << group_stats
      end
      
      # TODO: cache this day object, maybe in advance
      day_stats.merge!(Stats.touch_stats(day_sessions))
      day_stats.merge!(Stats.device_stats(day_sessions))
      day_stats.merge!(Stats.sensor_stats(day_sessions))
      day_stats.merge!(Stats.time_block_use_for_sessions(day_sessions))
      day_stats.merge!(Stats.parts_of_speech_stats(day_sessions))
      day_stats[:locations] = Stats.location_use_for_sessions(day_sessions)
      
      days[date.to_s] = {
        'total' => day_stats,
        'group_counts' => groups
      }
    end

    total_stats.merge!(Stats.touch_stats(sessions))
    total_stats.merge!(Stats.device_stats(sessions))
    total_stats.merge!(Stats.sensor_stats(sessions))
    total_stats.merge!(Stats.time_block_use_for_sessions(sessions))
    total_stats.merge!(Stats.parts_of_speech_stats(sessions))
    total_stats[:word_pairs] = Stats.word_pairs(sessions)
    total_stats[:days] = days
    total_stats[:locations] = Stats.location_use_for_sessions(sessions)
    
    summary.data ||= {}
    summary.data['stats'] = total_stats
    summary.data['session_ids'] = sessions.map(&:global_id)
    summary.save
    
    # TODO: create board-aligned stat summaries as well
  end

  def track_for_trends
    return true if self.user_id <= 0
    already_scheduled = Worker.scheduled_for?(:slow, self.class, :perform_action, {
      'method' => 'track_trends',
      'arguments' => [self.weekyear]
    })
    if !already_scheduled
      Worker.schedule_for(:slow, self.class, :perform_action, {
        'method' => 'track_trends',
        'arguments' => [self.weekyear]
      })
    end
    
    return true
  end
  
  def self.update_for_board(log_session)
    all = false
    return if !log_session || log_session.log_type != 'session'
    return unless log_session.user_id && log_session.started_at && log_session.data && log_session.data['stats']
    start_at = log_session.started_at.utc.beginning_of_week(:sunday)
    end_at = log_session.started_at.utc.end_of_week(:sunday)
    cweek = start_at.to_date.cweek
    cwyear = start_at.to_date.cwyear
    weekyear = (cwyear * 100) + cweek

    board_id_events.each do |board_id, board_clump|
      summary = WeeklyStatsSummary.find_or_create_by(:weekyear => weekyear, :board_id => board_id)
      sessions = LogSessionBoard.find_sessions(board_id, {:start_at => start_at, :end_at => end_at})
      
      total_stats = LogSessionBoard.init_stats(sessions)
    end
  end
  
  def self.track_trends(weekyear)
    start = 1.week.ago.to_date
    cweek = start.cweek
    cwyear = start.cwyear
    nowweekyear = (cwyear * 100) + cweek
    current_trends = weekyear >= nowweekyear


    sums = WeeklyStatsSummary.where(:weekyear => weekyear).where(['user_id > ?', 0])
    total = WeeklyStatsSummary.find_or_create_by(:weekyear => weekyear, :user_id => 0)
    
    total_keys = ['total_sessions', 'total_utterances', 'total_utterance_words', 
              'total_utterance_buttons', 'total_session_seconds']
              
    # clear the current tallies since we're reviewing all the data anyway
    total.data ||= {}
    total.data['totals'] = {}
    total_keys.each{|k| total.data['totals'][k] = 0 }
    total.data['totals']['total_users'] = 0
    total.data['totals']['total_modeled_words'] = 0
    total.data['totals']['total_modeled_buttons'] = 0
    total.data['totals']['total_words'] = 0
    total.data['totals']['total_buttons'] = 0
    total.data['totals']['total_core_words'] = 0
    total.data['word_counts'] = {}
    total.data['user_ids'] = []
    total.data['home_board_user_ids'] = []

    valid_words = WordData.standardized_words
    board_user_ids = {}
    word_pairs = {}
    home_boards = {}
    user_ids_with_home_boards = []
    sums.find_in_batches(batch_size: 10) do |batch|
      # TODO: sharding
      users = User.where(:id => batch.map(&:user_id))
      users.each do |user|
        total.data['user_ids'] << user.global_id
        total.data['home_board_user_ids'] << user.global_id if user.settings['preferences'] && user.settings['preferences']['home_board'] && user.settings['preferences']['home_board']['id']
        if current_trends
          if user.settings['preferences'] && user.settings['preferences']['home_board'] && user.settings['preferences']['home_board']['id']
            root_board = Board.find_by_path(user.settings['preferences']['home_board']['id'])
            while root_board && root_board.parent_board
              root_board = root_board.parent_board
            end
            if root_board
              local_board_id = root_board.id
              board_key = root_board.key || user.settings['preferences']['home_board']['key']
              home_boards[board_key] = (home_boards[board_key] || []) + [user.global_id] if root_board && root_board.public
              board_user_ids[local_board_id] ||= []
              board_user_ids[local_board_id] << user.global_id
            end
          end
        end
      end
      batch.each do |summary|
        # quick win with some basic, easy data to track
        total_keys.each do |key|
          total.data['totals'][key] += summary.data['stats'][key]
        end
        total.data['totals']['total_modeled_words'] += (summary.data['stats']['modeled_word_counts'] || {}).map(&:last).sum
        total.data['totals']['total_modeled_buttons'] += (summary.data['stats']['modeled_button_counts'] || {}).map{|k, h| h['count'] }.sum
        total.data['totals']['total_words'] += (summary.data['stats']['all_word_counts'] || {}).map(&:last).sum + summary.data['stats']['modeled_word_counts'].map(&:last).sum
        total.data['totals']['total_buttons'] += (summary.data['stats']['all_button_counts'] || {}).map{|k, h| h['count'] }.sum + (summary.data['stats']['modeled_button_counts'] || {}).map{|k, h| h['count'] }.sum
        total.data['totals']['total_core_words'] += summary.data['stats']['core_words']['core'] || 0
        total.data['totals']['total_users'] += 1
        summary.data['stats']['all_word_counts'].each do |word, cnt|
          if word && valid_words[word.downcase]
            total.data['word_counts'][word.downcase] = (total.data['word_counts'][word.downcase] || 0) + cnt 
          end
        end
        
        # iterate through events, tracking previous and (possibly) current spoken event
        # if there's a previous and current, and there hasn't been too long a delay
        # between them, and both words are included in a core word list, 
        # generate a one-way hash of the pairing and 
        # add the timestamp and user_id (if not already added) for the hash.
        (summary.data['stats']['word_pairs'] || {}).each do |k, pair|
          word_pairs[k] ||= {}
          word_pairs[k][:count] = (word_pairs[k][:count] || 0) + pair['count']
          word_pairs[k][:user_ids] ||= []
          word_pairs[k][:user_ids] << summary.user_id
          word_pairs[k]['a'] = pair['a']
          word_pairs[k]['b'] = pair['b']
        end
      end
    end

    # Get a list of all the words common to most user boards and record their frequency
    word_user_counts = {}    
    if current_trends
      board_ids = board_user_ids.map(&:first)
      BoardDownstreamButtonSet.where(:board_id => board_ids).find_in_batches(batch_size: 10) do |batch|
        batch.each do |button_set|
          button_set.data['buttons'].each do |button|
            word = button['label'].downcase
            if BoardDownstreamButtonSet.spoken_button?(button, nil) && valid_words[word]
              word_user_counts[word] = (word_user_counts[word] || []) + board_user_ids[button_set.board_id]
            end
          end
        end
      end
    end
    total.data['available_words'] = {}
    word_user_counts.each do |word, user_ids|
      user_ids.uniq!
      if user_ids.length >= 3 && user_ids.length > total.data['totals']['total_users'] / 3
        total.data['available_words'][word] = user_ids
      end
    end
    
    if current_trends
      total.data['home_boards'] = {}
      home_boards.each do |key, user_ids|
        user_ids.uniq!
        board = Board.find_by_path(key)
        board = board.parent_board if board.parent_board
        # at least 5 users need it as their home page, and it needs to be for at least .5% of users
        if user_ids.length >= 5 && user_ids.length >= total.data['totals']['total_users'] / 200
          total.data['home_boards'][key] = user_ids
        end
      end
    end
    
    # safe-ish stats row: total logged time, % modeling, % core words, average words per minute
    # unsafe stats row: total users, total sessions, sessions per user, total words
    # also: words available to % of users, most-common home boards

    total.data['word_pairs'] = {}
    total_sums = sums.count.to_f
    word_pairs.each do |k, pair|
      pair[:user_count] = pair[:user_ids].uniq.length
      pair.delete(:user_ids)
      # if at least 50 instances, or 1 in 500 have the pairing, let's include it
      if pair[:user_count] > 50 || (pair[:user_count] > 5 && (pair[:user_count].to_f / total_sums) > 0.002)
        total.data['word_pairs'][k] = pair
      end
    end
    total.data['word_matches'] = {}
    total.data['word_pairs'].each do |k, pair|
      total.data['word_matches'][pair['a']] ||= []
      total.data['word_matches'][pair['a']] << pair
      total.data['word_matches'][pair['b']] ||= []
      total.data['word_matches'][pair['b']] << pair
    end
    
    total.save
    total
  end
  
  def self.trends(include_admin=false)
    res = {}
    res['weeks'] = {}
    stash = {}
    start = 3.months.ago.to_date
    cweek = start.cweek
    cwyear = start.cwyear
    cutoffweekyear = (cwyear * 100) + cweek
    stash[:total_session_seconds] = 0
    stash[:modeled_buttons] = 0.0
    stash[:total_buttons] = 0
    stash[:core_words] = 0
    stash[:total_words] = 0
    stash[:user_ids] = []
    stash[:total_sessions] = 0
    stash[:total_words] = 0
    stash[:word_counts] = {}
    stash[:home_board_user_ids] = []
    earliest = nil
    latest = nil
    WeeklyStatsSummary.where(['weekyear >= ?', cutoffweekyear]).where(:user_id => 0).each do |summary|
      next unless summary.data && summary.data['totals']
      date = Date.commercial(summary.weekyear / 100, summary.weekyear % 100) - 1
      earliest = [earliest, date].compact.min
      latest = [latest, date].compact.max
      week = {
        'modeled_percent' => 100.0 * (summary.data['totals']['total_modeled_buttons'].to_f / summary.data['totals']['total_buttons'].to_f * 2.0).round(1) / 2.0,
        'core_percent' => 100.0 * (summary.data['totals']['total_core_words'].to_f / summary.data['totals']['total_words'].to_f * 2.0).round(1) / 2.0,
        'words_per_minute' => (summary.data['totals']['total_words'].to_f / summary.data['totals']['total_session_seconds'].to_f * 60.0).round(1)
      }
      res['weeks'][summary.weekyear] = week

      stash[:total_session_seconds] += summary.data['totals']['total_session_seconds']
      stash[:modeled_buttons] += summary.data['totals']['total_modeled_buttons']
      stash[:total_buttons] += summary.data['totals']['total_buttons']
      stash[:core_words] += summary.data['totals']['total_core_words']
      stash[:total_words] += summary.data['totals']['total_words']
      stash[:user_ids] += summary.data['user_ids'] || []
      stash[:total_sessions] += summary.data['totals']['total_sessions']
      stash[:home_board_user_ids] += summary.data['home_board_user_ids'] || summary.data['user_ids'] || []
      
      if summary.data['word_counts']
        summary.data['word_counts'].each do |word, cnt|
          stash[:word_counts][word] = (stash[:word_counts][word] || 0) + cnt
        end
      end
      
      if summary.data['available_words']
        summary.data['available_words'].each do |word, user_ids|
          stash[:available_words] ||= {}
          stash[:available_words][word] = (stash[:available_words][word] || []) + user_ids
        end
      end
      
      if summary.data['home_boards']
        stash[:home_boards] ||= {}
        summary.data['home_boards'].each do |key, user_ids|
          stash[:home_boards][key] ||= []
          stash[:home_boards][key] += user_ids
        end
      end
      
      if summary.data['word_pairs']
        stash[:word_pairs] ||= {}
        summary.data['word_pairs'].each do |k, pair|
          stash[:word_pairs][k] ||= {
            'a' => pair['a'],
            'b' => pair['b'],
            'count' => 0
          }
          stash[:word_pairs][k]['count'] += pair['count']
        end
      end
    end
    
    res[:started_at] = earliest && earliest.iso8601
    res[:ended_at] = latest && latest.iso8601
    res[:total_session_seconds] = stash[:total_session_seconds]
    res[:modeled_percent] = 100.0 * (stash[:modeled_buttons].to_f / stash[:total_buttons].to_f * 2.0).round(1) / 2.0
    res[:modeled_percent] = 0.0 if res[:modeled_percent].nan?

    res[:core_percent] = 100.0 * (stash[:core_words].to_f / stash[:total_words].to_f * 2.0).round(1) / 2.0
    res[:core_percent] = 0.0 if res[:core_percent].nan?
    res[:words_per_minute] = (stash[:total_words].to_f / stash[:total_session_seconds].to_f * 60.0).round(1)
    res[:words_per_minute] = 0.0 if res[:words_per_minute].nan?
    res[:research_communicators] = 500
    if include_admin
      res[:total_users] = stash[:user_ids].uniq.length
      res[:total_sessions] = stash[:total_sessions]
      res[:sessions_per_user] = (res[:total_sessions].to_f / res[:total_users].to_f).round(1)
      res[:sessions_per_user] = 0.0 if res[:sessions_per_user].nan?
      res[:total_words] = stash[:total_words]
    end
    
    if stash[:word_counts]
      max_word_count = stash[:word_counts].map(&:last).max || 0.0
      res[:max_word_count] = max_word_count if include_admin
      stash[:word_counts].each do |word, cnt|
        res[:word_counts] ||= {}
        res[:word_counts][word] = ((cnt.to_f / max_word_count.to_f * 10.0).round(1) / 10.0).round(2) if cnt > 10
      end
    end

    home_board_users = stash[:home_board_user_ids].uniq.length.to_f
    if stash[:home_boards]
      stash[:home_boards].each do |key, user_ids|
        res[:home_boards] ||= {}
        res[:home_boards][key] = ((user_ids.uniq.length.to_f / home_board_users * 10.0).round(1) / 10.0).round(2)
      end
    end
    
    if stash[:available_words] && include_admin
      stash[:available_words].each do |word, user_ids|
        res[:available_words] ||= {}
        res[:available_words][word] = ((user_ids.uniq.length.to_f / home_board_users * 10.0).round(1) / 10.0).round(2)
      end
    end
    
    if stash[:word_pairs] && include_admin
      max_word_pair = stash[:word_pairs].map{|k, p| p['count'] }.max || 0.0
      res[:max_word_pair] = max_word_pair if include_admin
      stash[:word_pairs].each do |k, pair|
        res[:word_pairs] ||= {}
        res[:word_pairs][k] = {
          'a' => pair['a'],
          'b' => pair['b'],
          'percent' => (pair['count'].to_f / max_word_pair.to_f * 2.0).round(1) / 2.0
        }
        res[:word_pairs][k]['percent'] = 0.0 if res[:word_pairs][k]['percent'].nan?
      end
    end
    
    # safe-ish stats row: total logged time, % modeling, % core words, average words per minute
    # unsafe stats row: total users, total sessions, sessions per user, total words
    # also: words available to % of users, most-common home boards
    # TODO: devices per communicator, supervisors per communicator, goals set, 
    
    res
  end
  
  def self.word_trends(word)
    word = word.downcase
    start = 8.weeks.ago.to_date
    cweek = start.cweek
    cwyear = start.cwyear
    cutoffweekyear = (cwyear * 100) + cweek
    earliest = nil
    latest = nil
    
    res = {}
    stash = {}
    stash[:user_ids] = []
    stash[:usage_count] = 0.0
    stash[:max_usage_count] = 0.0
    res[:weeks] = {}
    res[:pairs] = []

    stash[:home_board_user_ids] = []
    WeeklyStatsSummary.where(['weekyear >= ?', cutoffweekyear]).where(:user_id => 0).each do |summary|
      next unless summary.data && summary.data['totals']
      date = Date.commercial(summary.weekyear / 100, summary.weekyear % 100) - 1
      earliest = [earliest, date].compact.min
      latest = [latest, date].compact.max

      available_user_ids = (summary.data['available_words'] || {})[word] || []
      home_board_user_ids = summary.data['home_board_user_ids'] || summary.data['user_ids'] || []

      max_usage_count = summary.data['word_counts'].map(&:last).max
      usage_count = summary.data['word_counts'][word] || 0.0

      avail = (available_user_ids.length.to_f / home_board_user_ids.length.to_f).round(2)
      avail = 0.0 if avail.nan?
      usage = (usage_count.to_f / max_usage_count.to_f).round(2)
      usage = 0.0 if usage.nan?
      week = {
        'available_for' => avail,
        'usage_count' => usage
      }
      res[:weeks][summary.weekyear] = week
      stash[:home_board_user_ids] += home_board_user_ids
      stash[:user_ids] += summary.data['user_ids'] || []
      stash[:usage_count] += usage_count
      stash[:max_usage_count] += max_usage_count

      stash[:available_user_ids] ||= []
      stash[:available_user_ids] += available_user_ids
      
      (summary.data['word_matches'][word] || []).each do |pair|
        found = res[:pairs].detect{|p| [p['a'], p['b']].sort == [pair['a'], pair['b']].sort }
        if found
          found['count'] += pair['count']
          found['user_count'] += pair['user_count']
        else
          res[:pairs] << pair
        end
      end
    end

    if stash[:available_user_ids]
      res[:available_for] = (stash[:available_user_ids].uniq.length.to_f / stash[:home_board_user_ids].uniq.length.to_f).round(2)
      res[:available_for] = 0.0 if res[:available_for].nan?
    end
    res[:usage_count] = (stash[:usage_count].to_f / stash[:max_usage_count].to_f).round(2)
    res[:usage_count] = 0.0 if res[:usage_count].nan?
    
    max_user_count = res[:pairs].map{|p| p['user_count'] || 0 }.max
    max_count = res[:pairs].map{|p| p['count'] || 0 }.max
    res[:pairs].each do |pair|
      uc = pair.delete('user_count')
      c = pair.delete('count')
      pair['partner'] = pair['a'] == word ? pair['b'] : pair['a']
      pair['users'] = (uc.to_f / stash[:user_ids].uniq.length.to_f).round(2)
      pair['users'] = 0.0 if pair['users'].nan?
      pair['usages'] = (c.to_f / max_count.to_f).round(2)
      pair['usages'] = 0.0 if pair['usages'].nan?
    end
    
    res
  end
end
