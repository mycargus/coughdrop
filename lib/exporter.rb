module Exporter
  def self.export_logs(user_id, anonymized=false, zipper=nil)
    user = User.find_by_global_id(user_id)
    hash = log_json(user, LogSession.where(user_id: user.id), anonymized)
    ext = anonymized ? '.obla' : '.obl'
    fn = (anonymized ? "aac-logs-#{user.anonymized_identifier[0, 10]}" : "aac-logs-#{user.user_name}") + ext
    if zipper
      zipper.add("logs/#{fn}", JSON.pretty_generate(hash))
    else
      file = Tempfile.new(['log', ext])
      file.write(JSON.pretty_generate(hash))
      file.close
      Uploader.remote_upload("downloads/logs/user/#{Time.now.iso8601}/#{user.anonymized_identifier}/#{fn}", file.path, 'application/obl')
    end
  end
  
  def self.export_user(user_id)
    user = User.find_by_global_id(user_id)
    file = Tempfile.new(['user-data', '.zip'])
    file.close
    OBF::Utils.build_zip(file.path) do |zipper|
      zipper.add('README.txt', %{This zip file contains multiple resources representing a user export from CoughDrop:

- logs/aac-logs-something.obl is a full export of the user's data logs
- logs/aac-logs-something.obla is an anonymized export of the user's data logs
- settings.json is an export of the user's preferences and settings
- boards/home.obz is an export of the user's home board and sub-boards
- boards/sidebar-##.obz is an export of each of the user's sidebar boards
- boards/personal/something.obf or .obz are exports of the user's additional personal boards

More information about the file formats being used is available at https://www.openboardformat.org
})
      json = JsonApi::User.build_json(user, {:permissions => user})
      zipper.add('user.json', JSON.pretty_generate(json))
      export_logs(user.global_id, false, zipper)
      export_logs(user.global_id, true, zipper)
      export_boards(user, zipper)
    end
    Uploader.remote_upload("downloads/users/#{Time.now.iso8601}/#{user.user_name}/coughdrop-export-#{user.user_name}.zip", file.path, "application/zip")
  end
  
  def self.export_boards(user, zipper=nil)
    matched_board_ids = {}
    if user.settings['preferences']['home_board']
      home_board = Board.find_by_path(user.settings['preferences']['home_board']['id'] || user.settings['preferences']['home_board']['key'])
      if home_board
        matched_board_ids[home_board.global_id] = true
        home_board.settings['downstream_board_ids'].each{|id| matched_board_ids[id] = true }
        
        file = Tempfile.new(['home-board', '.obz'])
        path = file.path
        file.close
        Converters::CoughDrop.to_obz(home_board, path, {'user' => user})
        file = File.open(path, 'rb')
        zipper.add('boards/home.obz', file.read)
        file.close

        file = Tempfile.new(['home-board', '.pdf'])
        path = file.path
        file.close
        Converters::CoughDrop.to_pdf(home_board, path, {'user' => user, 'packet' => true})
        file = File.open(path, 'rb')
        zipper.add('boards/home.pdf', file.read)
        file.close
      end
    end
    user.sidebar_boards.each_with_index do |board, idx|
      sidebar_board = Board.find_by_path(board['id'] || board['key']) if board['key']
      if sidebar_board
        matched_board_ids[sidebar_board.global_id] = true
        sidebar_board.settings['downstream_board_ids'].each{|id| matched_board_ids[id] = true }
          
        file = Tempfile.new(['sidebar-board', '.obz'])
        path = file.path
        file.close
        Converters::CoughDrop.to_obz(sidebar_board, path, {'user' => user})
        file = File.open(path, 'rb')
        zipper.add("boards/sidebar-#{idx.to_s.rjust(2, '0')}.obz", file.read)
        file.close
      end
    end
    Board.where(user_id: user.id).find_in_batches(batch_size: 5) do |batch|
      batch.each do |board|
        next if matched_board_ids[board.global_id]
        file = Tempfile.new(['board', '.obf'])
        path = file.path
        file.close
        Converters::CoughDrop.to_obf(board, path)
        file = File.open(path, 'rb')
        zipper.add("boards/personal/board-#{board.global_id}.obf", file.read)
        file.close
      end
    end
    "boards/home.obz"
    "boards/sidebar-##.obz"
    "boards/personal/global_id.obf"
    # make a folder for home_board obz, a folder for sidebar obzs, 
    # and a folder for any other personal boards (not downstream from any of those)
  end
  
  def self.export_log(log_session_id, anonymized=false)
    log_session = LogSession.find_by_global_id(log_session_id)
    hash = log_json(log_session.user, [log_session], anonymized)
    ext = anonymized ? '.obla' : '.obl'
    file = Tempfile.new(['log', ext])
    file.write(JSON.pretty_generate(hash))
    file.close
    fn = (anonymized ? "aac-log-#{log_session.anonymized_identifier[0, 10]}" : "aac-log-#{log_session.global_id}") + ext
    Uploader.remote_upload("downloads/logs/log/#{Time.now.iso8601}/#{log_session.anonymized_identifier}/#{fn}", file.path, 'application/obl')
  end
  
  def self.log_json(user, sessions, anonymized=false)
    init_state(user, anonymized)
    
    header = log_json_header(user, anonymized)
    if sessions.respond_to?(:find_in_batches)
      sessions.find_in_batches(batch_size: 5) do |batch|
        batch.each do |session|
          if session.data && session.started_at && session.ended_at && ['session', 'assessment', 'note'].include?(session.log_type)
            log_json_session(session, header, anonymized) 
          end
        end
      end
    else
      sessions.each do |session|
        log_json_session(session, header, anonymized)
      end
    end
    header[:anonymized] = true if anonymized
    header
  end
  
  def self.log_json_header(user, anonymized=false)
    user_id = anonymized ? user.anonymized_identifier : user.global_id
    {
      format: 'open-board-log-0.1',
      user_id: "coughdrop:#{user_id}",
      source: "coughdrop",
      locale: 'en', # TODO: ...
      sessions: []
    }
  end
  
  def self.log_json_session(log_session, header, anonymized=false)
    header ||= log_json_header(log_session, anonymized)
    session_id = anonymized ? log_session.anonymized_identifier : log_session.global_id
    device_id = anonymized ? log_session.device.anonymized_identifier : log_session.device.global_id
    session_type = log_session.log_type || 'log'
    session_type = 'log' if session_type == 'session'
    session = {
      id: session_id,
      type: session_type,
      started: time_shift((log_session.started_at || log_session.created_at)),
      ended: time_shift((log_session.ended_at || log_session.updated_at)),
      device_id: device_id,
      events: []
    }
    session[:anonymized] = true if anonymized

    if log_session.log_type == 'session'
      event_session(log_session, session, session_id, anonymized)
    elsif log_session.log_type == 'note' && !anonymized
      note_session(log_session, session, session_id, anonymized)
    elsif log_session.log_type == 'assessment' && !anonymized
      assessment_session(log_session, session, session_id, anonymized)
    end
    header[:sessions] << session
    header
  end

  def self.event_session(log_session, session, session_id, anonymized)
    core_buttons = {}
    mods = {
      ':plural' => 'plural', 
      ':singular' => 'singular', 
      ':comparative' => 'comparative', 
      ':er' => 'comparative', 
      ':superlative' => 'superlative',
      ':est' => 'superlative', 
      ':possessive' => 'possessive', 
      ':\'s' => 'possessive', 
      ':past' => 'past', 
      ':ed' => 'past', 
      ':present-participle' => 'present-participle', 
      ':ing' => 'present-participle'
    }

    log_session.data['events'].each_with_index do |event, idx|
      next if event['skip']
      prev_event = log_session.data['events'][idx - 1] || event
      next_event = log_session.data['events'][idx + 1] || event
      e = {
        id: "#{session_id}:#{idx}",
        timestamp: time_shift(Time.at(event['timestamp']), Time.at(prev_event['timestamp']), Time.at(next_event['timestamp']))
      }
      if event['type'] == 'button' && event['button'] && event['button']['button_id'] == -1
        event['type'] = 'action'
        event['action'] = {
          'action' => event['button']['vocalization'] || event['button']['label'],
          'text' => event['button']['completion'] || event['button']['label']
        }
        if event['action']['action'].match(/&&/)
          actions = event['action']['action'].split(/&&/).map{|m| m.strip }
          event['action']['actions'] = actions
          event['action']['action'] = actions[0]
        end
      end
      if event['type'] == 'button'
        next_events = []
        log_session.data['events'][idx + 1..-1].each do |ne|
          if ne['type'] == 'action' && ne['action'] && (ne['button_triggered'] || (ne['timestamp'] - event['timestamp']) < 0.5)
            add = false
            add = true if ne['button_triggered']
            add = true if ne['action']['action'] == 'open_board'
            add = true if ne['action']['action'] == 'auto_home'
            add = true if ne['action']['action'] == 'beep' && event['button']['vocalization'] == ':beep'
            add = true if ne['action']['action'] == 'backspace' && event['button']['vocalization'] == ':backspace'
            add = true if ne['action']['action'] == 'home' && event['button']['vocalization'] == ':home'
            add = true if ne['action']['action'] == 'clear' && event['button']['vocalization'] == ':clear'
            add = true if ne['action']['action'] == 'back' && event['button']['vocalization'] == ':back'
            if add
              ne['skip'] = true
              next_events << ne
              next
            end
          end
          break
        end
        e['type'] = 'button'
        board_id = (event['button']['board'] || {})['id'] || 'none'
        e['button_id'] = anon("#{event['button']['button_id']}:#{board_id}")
        e['board_id'] = anon(board_id)
        e['spoken'] = event['button']['spoken'] == true || event['button']['spoken'] == nil
        e['label'] = event['button']['label']
        if event['button']['vocalization'] && !event['button']['vocalization'].strip.match(/^[\:\+]/)
          e['vocalization'] = event['button']['vocalization'] 
        end
        e['image_url'] = event['button']['image'] if event['button']['image'] && !anonymized
        e['core_word'] = !!event['button']['core_word'] if event['button']['core_word']
        e['core_word'] ||= WordData.core_for?(e['label'] || '', nil)
        if !e['core_word'] && anonymized
          e['label'] = lookup(e['label'])
          e['vocalization'] = lookup(e['vocalization'])
        else
          core_buttons["#{event['button']['button_id']}:#{board_id}"] = true if e['core_word']
        end
        e['actions'] = []
        if (event['button']['vocalization'] || '').strip.match(/^[\:\+]/)
          event['button']['vocalization'].split(/&&/).map{|v| v.strip }.each do |mod|
            a = {:action => mod}
            if mods[a[:action]]
              a[:action] = ':modification'
              a[:modification_type] = mods[a[:action]]
            end
            if a[:action].match(/^\+/) && anonymized
              a[:action] = "+???" 
              a[:redacted] = true
            end
            lookup_text(a, event['button']['completion'])
            e['actions'] << a
          end
        elsif event['button']['completion']
          (event['button']['vocalization'] || '').split(/&&/).map{|v| v.strip }.each do |mod|
            if mod == ':space'
              e['actions'] << lookup_text({:action => ':completion'}, lookup(event['button']['completion']))
            elsif mod == ':completion'
              # this shouldn't actually be possible, since there is no user-generated button to do this
              e['actions'] << lookup_text({:action => ':completion'}, lookup(event['button']['completion']))
            elsif (mod || '').match(/^\:/)
              if mods[mod]
                e['actions'] << lookup_text({
                  :action => ':modification', 
                  :modification_type => mods[mod]
                }, lookup(event['button']['completion']))
              else
                e['actions'] << lookup_text({:action => ':completion'}, lookup(mod))
              end
            end
          end
        end
        if next_events.length > 0
          next_events.each do |next_event|
            action = {action: ":#{next_event['action']['action']}"}
            if next_event['action']['new_id']
              dest_id = next_event['action']['new_id']['id']
              dest_id ||= Board.where(key: next_event['action']['new_id']['key']).select('id').first.global_id if next_event['action']['new_id']['key']
              action[:destination_board_id] = next_event['action']['new_id']['id']
            end
            e['actions'] << action
          end
        end
        e['actions'].uniq!
        if e['actions'].detect{|a| a[:action] == 'auto_home' }
          e['actions'] = a['actions'].select{|a| a[:action] != 'open_board' }
        end
        e.delete('actions') if e['actions'].empty?
      elsif event['type'] == 'action'
        e['type'] = 'action'
        e['action'] = "#{event['action']['action']}"
        e['action'] = ":#{e['action']}" unless e['action'].match(/^:/)
        e['action'] = ':prediction' if e['action'].match(/^:predict/)
        e['action'] = ':completion' if e['action'].match(/^:complet/)
        if e['action'] == ':completion' || e['action'] == ':prediction'
          lookup_text(e, event['action']['text'])
        elsif (e['action'] == ':auto_home' || e['action'] == ':open_board') && event['action']['new_id']
          dest_id = event['action']['new_id']['id']
          # TODO: record the missing board id when saving the log rather than when 
          # generating the log file for better accuracy
          dest_id ||= Board.where(key: event['action']['new_id']['key']).select('id').first.global_id if event['action']['new_id']['key']
          e['destination_board_id'] = dest_id if dest_id
        end
      elsif event['type'] == 'utterance'
        e['type'] = 'utterance'
        e['text'] = event['utterance']['text']
        sentence = []
        e['buttons'] = event['utterance']['buttons'].map do |button|
          if anonymized && !WordData.core_for?(button['label'] || '', nil) && (button['modified'] || !core_buttons["#{button['button_id']}:#{button['board']['id']}"])
            sentence << '????'
            {redacted: true}
          elsif button['modified'] # inflection, spelling with space, word completion, word prediction
            sentence << (button['vocalization'] || button['label'])
            lookup_text({action: ':completion'}, button['vocalization'] || button['label'])
          else
            sentence << (button['vocalization'] || button['label'])
            res = {
              id: button['button_id'],
              board_id: (button['board'] || {})['id'] || 'none',
              label: button['label'],
            }
            res[:vocalization] = button['vocalization'] if button['vocalization']
            res
          end
        end
        e['text'] = sentence.join(' ') if anonymized
      end

      e['modeling'] = event['modeling'] == true
      if log_session.geo_cluster
        e['location_id'] = anon(log_session.geo_cluster.global_id)
      end
      e['depth'] = event['depth'] if event['depth']
      e['parts_of_speech'] = event['parts_of_speech']['types'] if event['parts_of_speech']
      ['orientation', 'geo', 'ip_address', 'ssid', 'window_width', 'window_height', 
            'volume', 'ambient_light', 'screen_brightness', 'system' 'browser',
            'percent_x', 'percent_y'].each do |extra|
        e[extra] = event[extra] if event[extra] != nil
        e[extra] = event['button'][extra] if e[extra] == nil && event['button'] && event['button'][extra] != nil
      end
      ['ip_address', 'ssid'].each do |extra|
        if anonymized && e[extra]
          e[extra] = lookup(e[extra])
        end
      end
      e.delete('geo') if anonymized

      session[:events] << e
    end
    session
  end
    
  def self.note_session(log_session, session, session_id, anonymized)
    event = {
      id: "#{session_id}:note",
      timestamp: time_shift(log_session.started_at), 
      author_name: log_session.author.user_name,
      author_url: "#{JsonApi::Json.current_host}/#{log_session.author.user_name}",
      text: ''
    }
    if log_session.data['note']['text']
      event[:text] += log_session.data['note']['text']
    end
    if log_session.data['note']['video']
      event[:text] += " video recorded (#{log_session.data['note']['video']['duration']}s)"
    end
    if log_session.data['goal']
      event[:text] += " (related to goal \"#{log_session.data['goal']['summary']}\")"
      log_session[:goal_id] = log_session.data['goal']['id']
    end
    event[:text].strip!
    session[:events] << event
  end
  
  def self.assessment_session(log_session, session, session_id, anonymized)
    session[:assessment_description] = log_session.data['assessment']['description']
    session[:assessment_summary] = log_session.data['assessment']['summary']
    if log_session.data['goal']
      session[:goal_id] = log_session.data['goal']['id']
    end
    log_session.data['assessment']['tallies'].each_with_index do |tally, idx|
      session[:events] << {
        id: "#{session_id}:#{idx}",
        timestamp: time_shift(Time.at(tally['timestamp'])),
        correct: tally['correct']
      }
    end
  end
  
  def self.init_state(user, anonymized)
    if anonymized
      raise "user required" unless user
      @anonymizer = user
      @lookups = {}
    else
      @anonymizer = nil
      @lookups = nil
    end
    @time_offset = nil
  end

  def self.time_shift(time, before=nil, after=nil)
    if @anonymizer
      if !@time_offset
        starter = Time.parse('2000-01-01T00:00:00.00Z')
        @time_offset = time - starter
      end
      if before && after
        before_diff = (time - before).abs.to_f / 2
        after_diff = (after - time).abs.to_f / 2
        ((time.to_time - @time_offset) + (rand * (before_diff + after_diff) - before_diff)).utc.iso8601
      else
        (time.to_time - @time_offset).utc.iso8601
      end
    else
      time.utc.iso8601
    end
  end
  
  def self.anon(str)
    if @anonymizer
      @anonymizer.anonymized_identifier(str)
    else
      str
    end
  end
  
  def self.lookup(str)
    if @anonymizer
      @lookups[str] ||= anon(str)
    else
      str
    end
  end
  
  def self.lookup_text(hash, str)
    return hash unless hash && str
    if @anonymizer && !WordData.core_for?(str, nil)
      hash[:text] = lookup(str)
      hash[:redacted] = true
    else
      hash[:text] = str
    end
    hash
  end
  
  def self.process_obl(hash)
    raise "not implemented"
  end
end