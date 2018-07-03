require 'spec_helper'

describe Exporter do
  before(:each) do 
    Exporter.init_state(nil, false)
  end
  describe 'export_logs' do
    it 'should export logs and upload remotely' do
      u = User.create
      tmp = OpenStruct.new
      expect(Tempfile).to receive(:new).with(['log', '.obl']).and_return(tmp)
      expect(tmp).to receive(:write) do |str|
        json = JSON.parse(str)
        expect(json['format']).to eq('open-board-log-0.1')
      end
      expect(tmp).to receive(:close)
      expect(tmp).to receive(:path).and_return("pathy-wathy")
      expect(Uploader).to receive(:remote_upload) do |remote_path, path, content_type|
        expect(content_type).to eq('application/obl')
        expect(path).to eq("pathy-wathy")
        expect(remote_path).to match(/downloads\/logs\/user/)
        expect(remote_path).to match(u.reload.anonymized_identifier)
      end
      Exporter.export_logs(u.global_id)
    end

    it 'should export anonymized logs' do
      u = User.create
      tmp = OpenStruct.new
      expect(Tempfile).to receive(:new).with(['log', '.obla']).and_return(tmp)
      expect(tmp).to receive(:write) do |str|
        json = JSON.parse(str)
        expect(json['format']).to eq('open-board-log-0.1')
      end
      expect(tmp).to receive(:close)
      expect(tmp).to receive(:path).and_return("pathy-wathy")
      expect(Uploader).to receive(:remote_upload) do |remote_path, path, content_type|
        expect(content_type).to eq('application/obl')
        expect(path).to eq("pathy-wathy")
        expect(remote_path).to match(/downloads\/logs\/user/)
        expect(remote_path).to match(u.reload.anonymized_identifier)
      end
      Exporter.export_logs(u.global_id, true)
    end

    it 'should generate a zip if defined' do
      u = User.create
      expect(Tempfile).to_not receive(:new)
      zipper = OpenStruct.new
      expect(zipper).to receive(:add) do |fn, str|
        json = JSON.parse(str)
        expect(json['format']).to eq('open-board-log-0.1')
        expect(fn).to match(/aac-logs/)
      end
      Exporter.export_logs(u.global_id, false, zipper)
    end
  end

  describe 'export_user' do
    it 'should combine all the results' do
      u = User.create
      expect(Uploader).to receive(:remote_upload) do |remote_path, path, content_type|
        expect(remote_path).to match(/downloads\/users/)
        expect(remote_path).to match(u.user_name)
      end
      expect(JsonApi::User).to receive(:build_json).with(u, {:permissions => u}).and_return({})
      expect(Exporter).to receive(:export_logs).exactly(2).times
      expect(Exporter).to receive(:export_boards)
      Exporter.export_user(u.global_id)
    end
  end

  describe 'export_boards' do
    it 'should export home boards, sidebar boards, and any other user boards' do
      user = User.create
      home = Board.create(user: user)
      sidebar1 = Board.create(user: user)
      sidebar2 = Board.create(user: user)
      a = Board.create(user: user)
      b = Board.create(user: user)
      c = Board.create(user: user)
      d = Board.create(user: user)
      e = Board.create(user: user)
      a.process({'buttons' => [{'id' => 1, 'label' => 'a', 'load_board' => {'key' => b.key, 'id' => b.global_id}}]}, {user: user, author: user})
      home.process({'buttons' => [{'id' => 2, 'label' => 'x', 'load_board' => {'key' => d.key, 'id' => d.global_id}}]}, {user: user, author: user})
      sidebar2.process({'buttons' => [{'id' => 3, 'label' => 'f', 'load_board' => {'key' => e.key, 'id' => e.global_id}}]}, {user: user, author: user})

      Worker.process_queues
      expect(home.reload.settings['downstream_board_ids']).to eq([d.global_id])
      expect(sidebar2.reload.settings['downstream_board_ids']).to eq([e.global_id])
      user.settings['preferences']['home_board'] = {'id' => home.global_id, 'key' => home.key}
      user.settings['preferences']['sidebar_boards'] = [
        {'key' => sidebar1.key},
        {'key' => sidebar2.key}
      ]
      user.save!
      Worker.process_queues
      expect(Converters::CoughDrop).to receive(:to_obz) do |board, path, opts|
        if board == home || board == sidebar1 || board == sidebar2
          expect(opts).to eq({'user' => user})
        else
          expect(false).to eq(true)
        end
      end.exactly(3).times
      boards = []
      expect(Converters::CoughDrop).to receive(:to_obf) do |board, path|
        boards << board
      end.at_least(3).times
      zipper = OpenStruct.new
      expect(zipper).to receive(:add).at_least(6).times
      Exporter.export_boards(user, zipper)
      expect(boards.sort_by(&:id)).to eq([a, b, c])
    end
  end

  describe 'export_log' do
    it 'should generate the log' do
      user = User.create
      d = Device.create(user: user)
      session = LogSession.create(user: user, author: user, device: d)
      expect(Uploader).to receive(:remote_upload) do |remote_path, path, content_type|
        expect(path).to eq('path')
        expect(content_type).to eq('application/obl')
        expect(remote_path).to match(/downloads\/logs\/log/)
        expect(remote_path).to match(/\.obl/)
        expect(remote_path).to match(session.reload.anonymized_identifier)
      end
      expect(Exporter).to receive(:log_json).with(user, [session], false).and_return({})
      tmp = OpenStruct.new
      expect(Tempfile).to receive(:new).and_return(tmp)
      expect(tmp).to receive(:write).with("{\n}")
      expect(tmp).to receive(:close)
      expect(tmp).to receive(:path).and_return('path')
      Exporter.export_log(session.global_id, false)
    end

    it 'should generate an anonymized version' do
      user = User.create
      d = Device.create(user: user)
      session = LogSession.create(user: user, author: user, device: d)
      expect(Uploader).to receive(:remote_upload) do |remote_path, path, content_type|
        expect(path).to eq('path')
        expect(content_type).to eq('application/obl')
        expect(remote_path).to match(/downloads\/logs\/log/)
        expect(remote_path).to match(/\.obla/)
        expect(remote_path).to match(session.reload.anonymized_identifier)
      end
      expect(Exporter).to receive(:log_json).with(user, [session], true).and_return({})
      tmp = OpenStruct.new
      expect(Tempfile).to receive(:new).and_return(tmp)
      expect(tmp).to receive(:write).with("{\n}")
      expect(tmp).to receive(:close)
      expect(tmp).to receive(:path).and_return('path')
      Exporter.export_log(session.global_id, true)
    end
  end

  describe 'log_json' do
    it 'should generate a log file for the specified sessions' do
      u = User.create
      d = Device.create(user: u)
      s1 = LogSession.create(user: u, device: d, author: u)
      s2 = LogSession.create(user: u, device: d, author: u)
      hash = Exporter.log_json(u, [s1, s2])
      expect(hash[:format]).to eq('open-board-log-0.1')
      expect(hash[:sessions].length).to eq(2)
    end

    it 'should generate an anonymized version' do
      u = User.create
      d = Device.create(user: u)
      s1 = LogSession.create(user: u, device: d, author: u)
      s2 = LogSession.create(user: u, device: d, author: u)
      hash = Exporter.log_json(u, [s1, s2], true)
      expect(hash[:format]).to eq('open-board-log-0.1')
      expect(hash[:sessions].length).to eq(2)
      expect(hash[:anonymized]).to eq(true)
    end
  end

  describe 'log_json_header' do
    it 'should return the correct value' do
      u = User.create
      expect(Exporter.log_json_header(u, true)).to eq({
        format: 'open-board-log-0.1',
        user_id: "coughdrop:#{u.anonymized_identifier}",
        source: 'coughdrop',
        locale: 'en',
        sessions: []
      })
      expect(Exporter.log_json_header(u)).to eq({
        format: 'open-board-log-0.1',
        user_id: "coughdrop:#{u.global_id}",
        source: 'coughdrop',
        locale: 'en',
        sessions: []
      })
    end
  end

  describe 'log_json_session' do
    it 'should call the right kind of sub-method' do
      u = User.create
      d = Device.create(user: u)
      s1 = LogSession.create(user: u, device: d, author: u, :log_type => 'session')
      s1.log_type = 'session'
      s2 = LogSession.create(user: u, device: d, author: u, :data => {'note' => {}})
      s2.log_type = 'note'
      s3 = LogSession.create(user: u, device: d, author: u, :data => {'assessment' => {}})
      s3.log_type = 'assessment'
      expect(Exporter).to receive(:event_session).exactly(2).times
      expect(Exporter).to receive(:note_session).exactly(1).times
      expect(Exporter).to receive(:assessment_session).exactly(1).times
      res = Exporter.log_json_session(s1, {sessions: []}, false)
      expect(res[:sessions].length).to eq(1)
      res = Exporter.log_json_session(s1, {sessions: []}, true)
      expect(res[:sessions].length).to eq(1)
      res = Exporter.log_json_session(s2, {sessions: []}, false)
      expect(res[:sessions].length).to eq(1)
      res = Exporter.log_json_session(s2, {sessions: []}, true)
      expect(res[:sessions].length).to eq(1)
      res = Exporter.log_json_session(s3, {sessions: []}, false)
      expect(res[:sessions].length).to eq(1)
      res = Exporter.log_json_session(s3, {sessions: []}, true)
      expect(res[:sessions].length).to eq(1)
    end
  end

  describe 'event_session' do
    it 'should generate the correct information' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create()
      ts = Time.parse('Apr 7, 2017').to_i
      s1 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['13', '12']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['13.0001', '12.0001']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['13', '12.0001']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s4 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['13.0003', '12.0001']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s5 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['13.0001', '11.9999']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s6 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['18', '18']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.9'})
      s7 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['18.0001', '18.0001']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s8 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['18', '18.0001']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s9 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['18.0003', '18.0001']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s10 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['18.0001', '17.9999']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.9'})
      ClusterLocation.clusterize_geos(u.global_id)
      expect(ClusterLocation.count).to eq(2)
      ClusterLocation.all.each{|c| c.generate_stats(true) }
      
      geos = ClusterLocation.all.select{|c| c.geo? }
      expect(geos.length).to eq(2)
      geos = geos.sort_by{|i| i.data['geo'] }
      expect(geos.map{|c| c.geo_sessions.count }).to eq([5, 5])
      expect(geos.map{|c| c.data['geo'] }).to eq([[13.0001, 12.0001, 0], [18.0001, 18.0001, 0]])

      s1 = LogSession.process_new({'events' => [
        {'type' => 'button', 'modeling' => true, 'button' => {'label' => 'want', 'button_id' => 14, 'core' => true, 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13', '12'], 'timestamp' => ts - 5},
        {'type' => 'button', 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}, 'spoken' => false}, 'geo' => ['13', '12'], 'timestamp' => ts - 3, 'system' => 'iOS', 'browser' => 'Safari'},
        {'type' => 'button', 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13', '12'], 'timestamp' => ts - 1},
        {'type' => 'utterance', 'utterance' => {'text' => 'ok go ok', 'buttons' => [{'label' => 'ok'}, {'label' => 'cat', 'vocalization' => 'cat', 'modified' => true}, {'label' => 'want'}]}, 'geo' => ['13', '12'], 'timestamp' => ts},
        {'type' => 'button', 'button' => {'id' => -1, 'label' => ':completion', 'completion' => 'chicken'}, 'timestamp' => ts + 4, 'percent_x' => 0.9832, 'percent_y' => 0.2352523},
        {'type' => 'button', 'button' => {'id' => 4, 'board' => {'id' => 'asdf'}, 'label' => 'happy', 'vocalization' => 'I feel happy', 'image' => 'http://www.example.com/pi'}, 'timestamp' => ts + 6},
        {'type' => 'button', 'button' => {'id' => 5, 'board' => {'id' => 'asdf'}, 'label' => 'good', 'image' => 'http://www.example.com/pic.png'}, 'timestamp' => ts + 10},
        {'type' => 'action', 'action' => {'action' => 'auto_home', 'new_id' => {'id' => 'qwer'}}, 'timestamp' => ts + 10},
        {'type' => 'action', 'action' => {'action' => 'open_board', 'new_id' => {'id' => 'qwer'}}, 'timestamp' => ts + 12, 'button_triggered' => true},
        {'type' => 'action', 'action' => {'action' => 'open_board'}, 'timestamp' => ts + 14, 'volume' => 0.9, 'ambient_light' => 500, 'screen_brightness' => 0.5},
        {'type' => 'button', 'button' => {'id' => 5, 'board' => {'id' => 'asdf'}, 'label' => 'good', 'vocalization' => ':beep', 'image' => 'http://www.example.com/pic.png'}, 'timestamp' => ts + 20},
        {'type' => 'button', 'button' => {'id' => 55, 'board' => {'id' => 'asdf'}, 'label' => 'goody', 'vocalization' => ':beep &&   :home', 'image' => 'http://www.example.com/pic.png'}, 'timestamp' => ts + 21},
        {'type' => 'action', 'action' => {'action' => 'beep'}, 'timestamp' => ts + 20},
        {'type' => 'button', 'button' => {'id' => 6, 'board' => {'id' => 'asdf'}, 'label' => 'before', 'vocalization' => ':past-tense'}, 'timestamp' => ts + 25},
        {'type' => 'button', 'button' => {'id' => 7, 'board' => {'id' => 'asdf'}, 'completion' => 'happier', 'vocalization' => ':completion'}, 'timestamp' => ts + 30},
        {'type' => 'button', 'button' => {'id' => 8, 'board' => {'id' => 'asdf'}, 'completion' => 'wishing', 'parts_of_speech' => {'types' => ['adjective']}, 'vocalization' => ':plural'}, 'timestamp' => ts + 40},
        {'type' => 'action', 'action' => {'action' => 'bacon', 'text' => 'I love you'}, 'orientation' => {'alpha' => 20, 'beta' => 100, 'gamma' => -60}, 'timestamp' => ts + 100},
        {'type' => 'action', 'action' => {'action' => 'predict', 'text' => 'asked'}, 'ip_address' => '1.2.3.4', 'timestamp' => ts + 105},
        {'type' => 'action', 'action' => {'action' => 'open_board', 'new_id' => {'id' => 'fghj'}}, 'ssid' => 'xfinity-wifi', 'extra' => 1234, 'window_width' => 400, 'window_height' => 400, 'timestamp' => ts + 200},
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      ClusterLocation.clusterize_geos(u.global_id)
      ClusterLocation.all.each{|c| c.generate_stats(true) }
      s1.reload

      res = Exporter.event_session(s1, {events: []}, 'sesh', false)
      expect(res[:events].length).to eq(16)
      expect(JSON.parse(res[:events].to_json)).to eq(JSON.parse([
        {
          "id": "sesh:0",
          "timestamp": "2017-04-07T05:59:55Z",
          "type": "button",
          "button_id": "14:1_1",
          "board_id": "1_1",
          "spoken": true,
          "label": "want",
          "core_word": true,
          "modeling": true,
          "parts_of_speech": [
            "verb",
            "transitive verb",
            "noun",
            "intransitive verb"
          ],
          "geo": [
            "13",
            "12"
          ],
          "ip_address": "1.2.3.4",
        },
        {
          "id": "sesh:1",
          "timestamp": "2017-04-07T05:59:57Z",
          "type": "button",
          "button_id": "1:1_1",
          "board_id": "1_1",
          "spoken": false,
          "label": "ok go ok",
          "core_word": false,
          "modeling": false,
          "parts_of_speech": [
            "other"
          ],
          "geo": [
            "13",
            "12"
          ],
          "ip_address": "1.2.3.4",
        },
        {
          "id": "sesh:2",
          "timestamp": "2017-04-07T05:59:59Z",
          "type": "button",
          "button_id": "1:1_1",
          "board_id": "1_1",
          "spoken": true,
          "label": "ok go ok",
          "core_word": false,
          "modeling": false,
          "parts_of_speech": [
            "other"
          ],
          "geo": [
            "13",
            "12"
          ],
          "ip_address": "1.2.3.4"
        },
        {
          "id": "sesh:3",
          "timestamp": "2017-04-07T06:00:00Z",
          "type": "utterance",
          "text": "ok go ok",
          "buttons": [
            {
              "id": nil,
              "board_id": "none",
              "label": "ok"
            },
            {
              "action": ":completion",
              "text": "cat"
            },
            {
              "id": nil,
              "board_id": "none",
              "label": "want"
            }
          ],
          "modeling": false,
          "geo": [
            "13",
            "12"
          ],
          "ip_address": "1.2.3.4"
        },
        {
          "id": "sesh:4",
          "timestamp": "2017-04-07T06:00:04Z",
          "type": "button",
          "button_id": ":none",
          "board_id": "none",
          "spoken": true,
          "label": ":completion",
          "core_word": false,
          "modeling": false,
          "parts_of_speech": [
            "noun",
            "adjective"
          ],
          "ip_address": "1.2.3.4",
          "percent_x": 0.9832,
          "percent_y": 0.2352523
        },
        {
          "id": "sesh:5",
          "timestamp": "2017-04-07T06:00:06Z",
          "type": "button",
          "button_id": ":asdf",
          "board_id": "asdf",
          "spoken": true,
          "label": "happy",
          "vocalization": "I feel happy",
          "image_url": "http://www.example.com/pi",
          "core_word": true,
          "modeling": false,
          "parts_of_speech": [
            "other"
          ],
          "ip_address": "1.2.3.4"
        },
        {
          "id": "sesh:6",
          "timestamp": "2017-04-07T06:00:10Z",
          "type": "button",
          "button_id": ":asdf",
          "board_id": "asdf",
          "spoken": true,
          "label": "good",
          "image_url": "http://www.example.com/pic.png",
          "core_word": true,
          "actions": [
            {
              "action": ":auto_home",
              "destination_board_id": "qwer"
            },
            {
              "action": ":open_board",
              "destination_board_id": "qwer"
            }
          ],
          "modeling": false,
          "parts_of_speech": [
            "adjective",
            "interjection",
            "noun"
          ],
          "ip_address": "1.2.3.4"
        },
        {
          "id": "sesh:9",
          "timestamp": "2017-04-07T06:00:14Z",
          "type": "action",
          "action": ":open_board",
          "modeling": false,
          "ip_address": "1.2.3.4",
          "volume": 0.9,
          "ambient_light": 500,
          "screen_brightness": 0.5
        },
        {
          "id": "sesh:10",
          "timestamp": "2017-04-07T06:00:20Z",
          "type": "button",
          "button_id": ":asdf",
          "board_id": "asdf",
          "spoken": true,
          "label": "good",
          "image_url": "http://www.example.com/pic.png",
          "core_word": true,
          "actions": [
            {
              "action": ":beep"
            }
          ],
          "modeling": false,
          "ip_address": "1.2.3.4"
        },
        {
          "id": "sesh:12",
          "timestamp": "2017-04-07T06:00:21Z",
          "type": "button",
          "button_id": ":asdf",
          "board_id": "asdf",
          "spoken": true,
          "label": "goody",
          "image_url": "http://www.example.com/pic.png",
          "core_word": false,
          "actions": [
            {
              "action": ":beep",
            },
            {
              "action": ":home"
            }
          ],
          "modeling": false,
          "ip_address": "1.2.3.4"
        },
        {
          "id": "sesh:13",
          "timestamp": "2017-04-07T06:00:25Z",
          "type": "button",
          "button_id": ":asdf",
          "board_id": "asdf",
          "spoken": true,
          "label": "before",
          "core_word": true,
          "actions": [
            {
              "action": ":past-tense"
            }
          ],
          "modeling": false,
          "ip_address": "1.2.3.4"
        },
        {
          "id": "sesh:14",
          "timestamp": "2017-04-07T06:00:30Z",
          "type": "button",
          "button_id": ":asdf",
          "board_id": "asdf",
          "spoken": true,
          "label": nil,
          "core_word": false,
          "actions": [
            {
              "action": ":completion",
              "text": "happier"
            }
          ],
          "modeling": false,
          "ip_address": "1.2.3.4"
        },
        {
          "id": "sesh:15",
          "timestamp": "2017-04-07T06:00:40Z",
          "type": "button",
          "button_id": ":asdf",
          "board_id": "asdf",
          "spoken": true,
          "label": nil,
          "core_word": false,
          "actions": [
            {
              "action": ":modification",
              "modification_type": nil,
              "text": "wishing"
            }
          ],
          "modeling": false,
          "ip_address": "1.2.3.4"
        },
        {
          "id": "sesh:16",
          "timestamp": "2017-04-07T06:01:40Z",
          "type": "action",
          "action": ":bacon",
          "modeling": false,
          "orientation": {
            "alpha": 20,
            "beta": 100,
            "gamma": -60
          },
          "ip_address": "1.2.3.4"
        },
        {
          "id": "sesh:17",
          "timestamp": "2017-04-07T06:01:45Z",
          "type": "action",
          "action": ":prediction",
          "text": "asked",
          "modeling": false,
          "ip_address": "1.2.3.4"
        },
        {
          "id": "sesh:18",
          "timestamp": "2017-04-07T06:03:20Z",
          "type": "action",
          "action": ":open_board",
          "destination_board_id": "fghj",
          "modeling": false,
          "ip_address": "1.2.3.4",
          "ssid": "xfinity-wifi",
          "window_width": 400,
          "window_height": 400
        }
      ].to_json))
    end

    it 'should anonymize all information' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create()
      ts = Time.parse('Apr 7, 2017').to_i
      s1 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['13', '12']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['13.0001', '12.0001']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['13', '12.0001']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s4 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['13.0003', '12.0001']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s5 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['13.0001', '11.9999']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s6 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['18', '18']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.9'})
      s7 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['18.0001', '18.0001']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s8 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['18', '18.0001']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s9 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['18.0003', '18.0001']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s10 = LogSession.process_new({'events' => [{'timestamp' => Time.now.to_i, 'geo' => ['18.0001', '17.9999']}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.9'})
      ClusterLocation.clusterize_geos(u.global_id)
      expect(ClusterLocation.count).to eq(2)
      ClusterLocation.all.each{|c| c.generate_stats(true) }
      expect(s1.reload.geo_cluster_id).to_not eq(nil)
      expect(s2.reload.geo_cluster_id).to_not eq(nil)
      expect(s3.reload.geo_cluster_id).to_not eq(nil)
      expect(s4.reload.geo_cluster_id).to_not eq(nil)
      expect(s5.reload.geo_cluster_id).to_not eq(nil)
      expect(s6.reload.geo_cluster_id).to_not eq(nil)
      expect(s7.reload.geo_cluster_id).to_not eq(nil)
      expect(s8.reload.geo_cluster_id).to_not eq(nil)
      expect(s9.reload.geo_cluster_id).to_not eq(nil)
      expect(s10.reload.geo_cluster_id).to_not eq(nil)
      
      geos = ClusterLocation.all.select{|c| c.geo? }
      expect(geos.length).to eq(2)
      geos = geos.sort_by{|i| i.data['geo'] }
      expect(geos.map{|c| c.geo_sessions.count }).to eq([5, 5])
      expect(geos.map{|c| c.data['geo'] }).to eq([[13.0001, 12.0001, 0], [18.0001, 18.0001, 0]])

      s1 = LogSession.process_new({'events' => [
        {'type' => 'button', 'modeling' => true, 'button' => {'label' => 'want', 'button_id' => 14, 'core' => true, 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13', '12'], 'timestamp' => ts - 5, 'ssid' => 'xfinity-wifi'},
        {'type' => 'button', 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}, 'spoken' => false}, 'geo' => ['13', '12'], 'timestamp' => ts - 3, 'system' => 'iOS', 'browser' => 'Safari', 'ssid' => 'home-wifi'},
        {'type' => 'button', 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13', '12'], 'timestamp' => ts - 1},
        {'type' => 'utterance', 'utterance' => {'text' => 'ok go ok', 'buttons' => [{'label' => 'ok'}, {'label' => 'cat', 'vocalization' => 'cat', 'modified' => true}, {'label' => 'want'}]}, 'geo' => ['13', '12'], 'timestamp' => ts},
        {'type' => 'button', 'button' => {'id' => -1, 'label' => ':completion', 'completion' => 'chicken'}, 'timestamp' => ts + 4, 'percent_x' => 0.9832, 'percent_y' => 0.2352523},
        {'type' => 'button', 'button' => {'id' => 4, 'board' => {'id' => 'asdf'}, 'label' => 'happy', 'vocalization' => 'I feel happy', 'image' => 'http://www.example.com/pi'}, 'timestamp' => ts + 6},
        {'type' => 'button', 'button' => {'id' => 5, 'board' => {'id' => 'asdf'}, 'label' => 'good', 'image' => 'http://www.example.com/pic.png'}, 'timestamp' => ts + 10},
        {'type' => 'action', 'action' => {'action' => 'auto_home', 'new_id' => {'id' => 'qwer'}}, 'timestamp' => ts + 10},
        {'type' => 'action', 'action' => {'action' => 'open_board', 'new_id' => {'id' => 'qwer'}}, 'timestamp' => ts + 12, 'button_triggered' => true},
        {'type' => 'action', 'action' => {'action' => 'open_board'}, 'timestamp' => ts + 14, 'volume' => 0.9, 'ambient_light' => 500, 'screen_brightness' => 0.5},
        {'type' => 'button', 'button' => {'id' => 5, 'board' => {'id' => 'asdf'}, 'label' => 'good', 'vocalization' => ':beep', 'image' => 'http://www.example.com/pic.png'}, 'timestamp' => ts + 20},
        {'type' => 'action', 'action' => {'action' => 'beep'}, 'timestamp' => ts + 20},
        {'type' => 'button', 'button' => {'id' => 6, 'board' => {'id' => 'asdf'}, 'label' => 'before', 'vocalization' => ':past-tense'}, 'timestamp' => ts + 25},
        {'type' => 'button', 'button' => {'id' => 7, 'board' => {'id' => 'asdf'}, 'completion' => 'happier', 'vocalization' => ':completion'}, 'timestamp' => ts + 30},
        {'type' => 'button', 'button' => {'id' => 8, 'board' => {'id' => 'asdf'}, 'completion' => 'wishing', 'parts_of_speech' => {'types' => ['adjective']}, 'vocalization' => ':plural'}, 'timestamp' => ts + 40},
        {'type' => 'action', 'action' => {'action' => 'bacon', 'text' => 'I love you'}, 'orientation' => {'alpha' => 20, 'beta' => 100, 'gamma' => -60}, 'timestamp' => ts + 100},
        {'type' => 'action', 'action' => {'action' => 'predict', 'text' => 'asked'}, 'ip_address' => '1.2.3.4', 'timestamp' => ts + 105},
        {'type' => 'action', 'action' => {'action' => 'open_board', 'new_id' => {'id' => 'fghj'}}, 'ssid' => 'xfinity-wifi', 'extra' => 1234, 'window_width' => 400, 'window_height' => 400, 'timestamp' => ts + 200},
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      ClusterLocation.clusterize_geos(u.global_id)
      ClusterLocation.all.each{|c| c.generate_stats(true) }
      geos = ClusterLocation.all.select{|c| c.geo? }
      s1.geo_cluster_id = geos[0].id
      s1.save!
      expect(geos.length).to eq(2)
      expect(s1.reload.geo_cluster).to_not eq(nil)

      Exporter.init_state(u, true)
      res = Exporter.event_session(s1, {events: []}, 'sesh', true)
      expect(res[:events].length).to eq(15)
      expect(res[:events][0][:id]).to eq('sesh:0')
      expect(res[:events][0][:timestamp]).to be > "1999-12-31T23:58:00Z"
      expect(res[:events][0][:timestamp]).to be < "2000-01-01T00:00:00Z"
      expect(res[:events][14][:timestamp]).to be > "2000-01-01T00:02:30Z"
      expect(res[:events][14][:timestamp]).to be < "2000-01-01T00:03:30Z"
      expect(res[:events][0]['ssid']).to eq(res[:events][14]['ssid'])
      expect(res[:events][0]['ssid'].length).to be > 10
      expect(res[:events][0]['ssid']).to_not eq('xfinity-wifi')
      expect(res[:events][0]['button_id'].length).to be > 10
      expect(res[:events][0]['board_id'].length).to be > 10
      expect(res[:events][0]['location_id'].length).to be > 10
      expect(res[:events][0]['ip_address'].length).to be > 10
      expect(res[:events][0]['ip_address'].length).to_not eq('1.2.3.4')
      expect(res[:events][0]['location_id']).to eq(res[:events][1]['location_id'])
      expect(res[:events][0]['label']).to eq('want')
      expect(res[:events][1]['label']).to_not eq('ok go ok')
      expect(res[:events][1]['label'].length).to be > 15
      expect(res[:events][0]['geo']).to eq(nil)
    end
  end

  describe 'note_session' do
    it 'should generate the data' do
      now = Time.now
      expect(Time).to receive(:now).and_return(now).at_least(1).times
      hash = {events: []}
      u = User.create
      d = Device.create(user: u)
      session = LogSession.create(user: u, author: u, device: d, data: {
        'note' => {
          'text' => 'hello friend',
          'video' => {'duration' => 5}
        }
      })
      Exporter.note_session(session, hash, 'sesh', false)
      expect(hash).to eq({
        "events": [
          {
            "id": "sesh:note",
            "timestamp": Time.now.utc.iso8601,
            "author_name": "no-name",
            "author_url": "http://localhost:3000/no-name",
            "text": "hello friend video recorded (5s)"
          }
        ]        
      })
    end
  end

  describe 'assessment_session' do
    it 'should generate the data' do
      hash = {:events => []}
      u = User.create
      d = Device.create(user: u)
      session = LogSession.create(user: u, device: d, author: u, data: {
        'assessment' => {
          'description' => 'good assessment',
          'summary' => 'cool stuff',
          'tallies' => [
            {'timestamp' => 1527180207, 'correct' => false},
            {'timestamp' => 1527180217, 'correct' => true},
            {'timestamp' => 1527180227, 'correct' => true},
            {'timestamp' => 1527180237, 'correct' => false},
          ]
        }
      })
      Exporter.assessment_session(session, hash, 'asdf', false)
      expect(hash).to eq({
        events: [
          {
            id: "asdf:0",
            timestamp: "2018-05-24T16:43:27Z",
            correct: false
          },
          {
            id: "asdf:1",
            timestamp: "2018-05-24T16:43:37Z",
            correct: true
          },
          {
            id: "asdf:2",
            timestamp: "2018-05-24T16:43:47Z",
            correct: true
          },
          {
            id: "asdf:3",
            timestamp: "2018-05-24T16:43:57Z",
            correct: false
          }
        ],
        assessment_description: "good assessment",
        assessment_summary: "(0 correct, 0 incorrect)"
      })
    end
  end

  describe 'init_state' do
    it 'should initialize correctly' do
      Exporter.init_state('asdf', false)
      expect(Exporter.instance_variable_get('@anonymizer')).to eq(nil)
      expect(Exporter.instance_variable_get('@lookups')).to eq(nil)
      Exporter.init_state('asdf', false)
      expect(Exporter.instance_variable_get('@anonymizer')).to eq(nil)
      expect(Exporter.instance_variable_get('@lookups')).to eq(nil)
      Exporter.init_state('asdf', true)
      expect(Exporter.instance_variable_get('@anonymizer')).to eq('asdf')
      expect(Exporter.instance_variable_get('@lookups')).to eq({})
    end
  end
  
  describe 'anon' do
    it 'should call anonymization if defined' do
      Exporter.init_state(nil, false)
      expect(Exporter.anon('asdf')).to eq('asdf')
      anon = OpenStruct.new
      Exporter.init_state(anon, false)
      expect(Exporter.anon('asdf')).to eq('asdf')
      Exporter.init_state(anon, true)
      expect(anon).to receive(:anonymized_identifier).with('bacon').and_return('whatever')
      expect(Exporter.anon('bacon')).to eq('whatever')
    end
  end
  
  describe 'lookup' do
    it 'should call anonymization when appropriate' do
      Exporter.init_state(nil, false)
      expect(Exporter.lookup('asdf')).to eq('asdf')
      anon = OpenStruct.new
      expect(anon).to receive(:anonymized_identifier).with('bacon').and_return('whatever').exactly(1).times
      Exporter.init_state(anon, false)
      expect(Exporter.lookup('bacon')).to eq('bacon')
      Exporter.init_state(anon, true)
      expect(Exporter.lookup('bacon')).to eq('whatever')
      expect(Exporter.lookup('bacon')).to eq('whatever')
      expect(Exporter.lookup('bacon')).to eq('whatever')
    end
  end
  
  describe 'lookup_text' do
    it 'should anonymize core words if enabled' do
      Exporter.init_state(nil, false)
      expect(Exporter.lookup_text({}, 'asdf')).to eq({text: 'asdf'})
      expect(Exporter.lookup_text({}, 'like')).to eq({text: 'like'})
      anon = OpenStruct.new
      expect(anon).to receive(:anonymized_identifier) do |str|
        str + "-anon"
      end.at_least(1).times
      Exporter.init_state(anon, false)
      expect(Exporter.lookup_text({}, 'bacon')).to eq({text: 'bacon'})
      expect(Exporter.lookup_text({}, 'like')).to eq({text: 'like'})
      Exporter.init_state(anon, true)
      expect(Exporter.lookup_text({}, 'bacon')).to eq({text: 'bacon-anon', redacted: true})
      expect(Exporter.lookup_text({a: 1}, 'silliest')).to eq({text: 'silliest-anon', redacted: true, a:1})
      expect(Exporter.lookup_text({}, 'like')).to eq({text: 'like'})
    end
  end

  describe 'process_obl' do
  end
#   def self.process_obl(hash)
#     raise "not implemented"
#   end
# end
end
