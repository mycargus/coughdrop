module Exporter
#   def self.export_logs(user, anonymized=false, zipper=nil)
#     
#   end
#   
#   def self.export_user(user)
#     export_logs(user, zipper)
#     export_logs(user, true, zipper)
#     export_boards(user, zipper)
#   end
#   
#   def self.export_boards(user, zipper=nil)
#   end
#   
#   def self.init_state(user, anonymized)
#     if anonymized
#       raise "user required" unless user
#       @anonymizer = user
#       @lookups = {}
#     else
#       @anonymizer = nil
#       @lookups = nil
#     end
#   end
#   
#   def self.anon(str)
#     if @anonymizer
#       @anonymizer.anonymized_identifier(str)
#     else
#       str
#     end
#   end
#   
#   def self.lookup(str)
#     if @anonymizer
#       @lookups[str] ||= anon(str)
#     else
#       str
#     end
#   end
# 
#   def self.log_json_header(session, anonymized=false)
#     user = session.user
#     user_id = anonymized ? user.anonymized_identifier : user.global_id
#     {
#       format: 'open-board-log-0.1',
#       user_id: "coughdrop:#{user_id}",
#       source: "coughdrop",
#       locale: 'en', # TODO: ...
#       sessions: []
#     }
#   end
#   
#   def self.log_json(user, sessions, anonymized=false)
#     init_state(user, anonymized)
#     
#     header = log_json_header(log_session, anonymized)
#     sessions.each so |session|
#       log_json_session(session, header, anonymized)
#     end
#     header
#   end
#   
#   def self.log_json_session(log_session, header, anonymized=false)
#     header ||= log_json_header(log_session, anonymized)
#     session_id = anonymized ? log_session.anonymized_identifier : log_session.global_id
#     device_id = anonymized ? log_session.device.anonymized_identifier : log_session.device.global_id
#     session_type = log_session.log_type || 'log'
#     session_type = 'log' if session_type == 'session'
#     session = {
#       id: session_id,
#       type: session_type
#       started: log_session.started_at.utc.iso8601,
#       ended: log_session.ended_at.utc.iso8601,
#       device_id: device_id,
#       events: []
#     }
# 
#     if log_session.log_type == 'session'
#       event_session(log_session, session)
#     elsif log_session.log_type == 'note'
#       return nil if anonymized
#       note_session(log_session, session)
#     elsif log_session.log_type == 'assessment'
#       return nil if anonymized
#       assessment_session(log_session, session)
#     end
#     header[:sessions] << session
#   end
# 
#   def self.event_session(log_session, session)
#     core_buttons = {}
#     mods = {
#       ':plural' => 'plural', 
#       ':singular' => 'singular', 
#       ':comparative' => 'comparative', 
#       ':er' => 'comparative', 
#       ':superlative' => 'superlative',
#       ':est' => 'superlative', 
#       ':possessive' => 'possessive', 
#       ':\'s' => 'possessive', 
#       ':past' => 'past', 
#       ':ed' => 'past', 
#       ':present-participle' => 'present-participle', 
#       ':ing' => 'present-participle'
#     }
# 
#     log_session.data['events'].each_with_index do |event, idx|
#       next if ne['skip']
#       e = {
#         id: "#{session_id}:#{idx}",
#         timestamp: Time.at(event['timestamp']).utc.iso8601
#       }
#       if event['type'] == 'button'
#         next_events = []
#         log_session.data['events'][idx + 1..-1].each do |ne|
#           if ne['type'] == 'action' && ne['action'] && (ne['button_triggered'] || () < 1000)
#             add = false
#             add = true if ne['button_triggered']
#             add = true if ne['action']['action'] == 'open_board'
#             add = true if ne['action']['action'] == 'auto_home'
#             add = true if ne['action']['action'] == 'beep' && event['button']['vocalization'] == ':beep'
#             add = true if ne['action']['action'] == 'backspace' && event['button']['vocalization'] == ':backspace'
#             add = true if ne['action']['action'] == 'home' && event['button']['vocalization'] == ':home'
#             add = true if ne['action']['action'] == 'clear' && event['button']['vocalization'] == ':clear'
#             add = true if ne['action']['action'] == 'back' && event['button']['vocalization'] == ':back'
#             if add
#               ne['skip'] = true
#               next_events << ne
#               next
#             end
#           end
#           break
#         end
#         e['button_id'] = anon("#{event['button']['button_id']}:#{event['button']['board']['id']}")
#         e['board_id'] = anon(event['button']['board']['id'])
#         e['spoken'] = event['button']['spoken'] == true || event['button']['spoken'] == nil
#         e['label'] = event['button']['label']
#         e['vocalization'] = event['button']['vocalization'] if event['button']['vocalization'] && !event['button']['vocalization'].match(/^[\:\+]/)
#         e['image_url'] = event['button']['image'] if even['button']['image'] && !anonymized
#         e['core_word'] = !!event['button']['core_word'] if event['button']['core_word']
#         if !e['core_word'] && anonymized
#           e['label'] = lookup(e['label'])
#           e['vocalizatoin'] = lookup(e['vocalization'])
#         else
#           core_buttons[e['button_id']] = true if e['core_word']
#         end
#         e['actions'] = []
#         if event['button']['vocalization'].match(/^[\:\+]/)
#           event['actions'] << {:action => event['vocalization']}
#         elsif event['button']['completion']
#           if event['button']['vocalization'] == ':space'
#             event['actions'] << {:action => ':completion', :text => lookup(event['button']['completion'])}
#           elsif event['button']['vocalization'] == ':completion'
#             # this shouldn't actually be possible, since there is no user-generated button to do this
#             event['actions'] << {:action => ':completion', :text => lookup(event['button']['completion'])}
#           elsif event['button']['vocalization'].match(/^\:/)
#             if mods[event['button']['vocalization']]
#               event['actions'] << {
#                 :action => ':modification', 
#                 :text => event['button']['completion'],
#                 :modification_type => mods[event['button']['vocalization']]
#               }
#             else
#               event['actions'] << {:action => ':completion', :text => lookup(event['button']['completion'])}
#             end
#           end
#         end
#         if next_events.length > 0
#           next_events.each do |ne|
#             action = {action: ":#{ne['action']['action']}"}
#             if ne['action']['new_id']
#               action[:board_id] = new['action']['new_id']['id']
#             end
#           end
#         end
#         e['actions'].uniq!
#         if e['actions'].detect{|a| a[:action] == 'auto_home' }
#           e['actions'] = a['actions'].select{|a| a[:action] != 'open_board' }
#         end
#         e.delete('actions') if e['actions'].empty?
#       elsif event['type'] == 'action'
#         e['action'] = ":#{event['action']['action']}"
#         if (e['action'] == ':auto_home' || e['action'] == ':open_board') && event['action']['new_id']
#           dest_id = event['action']['new_id']['id']
#           # TODO: record the missing board id when saving the log rather than when 
#           # generating the log file for better accuracy
#           dest_id ||= Board.where(key: event['action']['new_id']['key']).select('id').first.global_id if event['action']['new_id']['key']
#           e['destination_board_id'] = dest_id if dest_id
#         end
#       elsif event['type'] == 'utterance'
#         e['text'] = event['utterance']['text']
#         sentence = []
#         e['buttons'] = event['utterance']['buttons'].map do |button|
#           if anonymized && (button['modified'] || !core_buttons["#{button['button_id']:#{button['board']['id']}"])
#             sentence << '????'
#             {redacted: true}
#           elsif button['modified'] # inflection, spelling with space, word completion, word prediction
#             sentence << button['vocalization'] || button['label']
#             {action: ':completion', text: button['vocalizaton'] || button['label']}
#           else
#             sentence << button['vocalization'] || button['label']
#             res = {
#               id: button['button_id'],
#               board_id: button['board']['id'],
#               label: button['label'],
#             }
#             res[:vocalization] = button['vocalization'] if button['vocalization']
#             res
#           end
#         end
#         e['text'] = sentence.join(' ') if anonymized
#       end
# 
#       e['modeling'] = event['modeling'] == true
#       if log_session.geo_cluster
#         e['location_id'] = anon(log_session.geo_cluster.global_id)
#       end
#       e['depth'] = event['depth'] if event['depth']
#       e['parts_of_speech'] = event['parts_of_speech']['types'] if event['parts_of_speech']
#       ['orientation', 'geo', 'ip_address', 'ssid', 'window_width', 'window_height', 
#             'volume', 'ambient_light', 'screen_brightness', 'system' 'browser',
#             'percent_x', 'percent_y'].each do |extra|
#         e[extra] = event[extra] if event[extra] != nil
#         e[extra] = event['button'][extra] if e[extra] == nil && event['button'] && event['button'][extra] != nil
#       end
#       ['ip_address', 'ssid'].each do |extra|
#         if anonymized && e[extra]
#         end
#       end
#       e.delete('geo') if anonymized
# 
#       session[:events] << e
#     end
#   end
#     
#   def self.note_session(log_session, session)
#     event = {
#       id: "#{session_id}:note",
#       timestamp: log_session.started_at.utc.iso8601, 
#       author_name: log_session.author.user_name,
#       author_url: "#{JsonApi::Json.current_host}/#{log_session.author.user_name}"
#       text: ''
#     }
#     if log_session.data['note']['text']
#       event[:text] += log_session.data['note']['text']
#     end
#     if log_session.data['note']['video']
#       event[:text] += " video recorded (#{log_session.data['note']['video']['duration']}s)"
#     end
#     if log_session.data['goal']
#       event[:text] += " (related to goal \"#{log_session.data['goal']['summary']}\")"
#       log_session[:goal_id] = log_session.data['goal']['id']
#     end
#     event[:text].strip!
#     session[:events] << event
#   end
#   
#   def self.assessment_session(log_session, session)
#     session[:assessment_description] = log_session.data['assessment']['description']
#     session[:assessment_summary] = log_session.data['assessment']['summary']
#     if log_session.data['goal']
#       session[:goal_id] = log_session.data['goal']['id']
#     end
#     log_session.data['assessment']['tallies'].each_with_index do |tally, idx|
#       session[:events] << {
#         id: "#{session_id}:#{idx}",
#         timestamp: Time.at(tally['timestamp']).utc.iso8601,
#         correct: tally['correct']
#       }
#     end
#   end
end