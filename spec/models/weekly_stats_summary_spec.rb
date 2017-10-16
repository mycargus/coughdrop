require 'spec_helper'

describe WeeklyStatsSummary, :type => :model do
  it "should error if no index defined" do
    expect { WeeklyStatsSummary.create }.to raise_error("no summary index defined")
  end
  
  it "should generate cached stats tied to a specific log" do
    u = User.create
    d = Device.create
    expect(ClusterLocation).to receive(:clusterize_cutoff).and_return(Date.parse('2015-01-01')).at_least(1).times
    s1 = LogSession.process_new({'events' => [
      {'type' => 'button', 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
      {'type' => 'button', 'modeling' => true, 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
      {'type' => 'button', 'modeling' => true, 'button' => {'spoken' => true, 'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
      {'type' => 'utterance', 'utterance' => {'text' => 'ok go ok', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => 1431029747}
    ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
    s2 = LogSession.process_new({'events' => [
      {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => 1430856977}
    ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
    
    ClusterLocation.clusterize_ips(u.global_id)
    ClusterLocation.clusterize_geos(u.global_id)
    ip_cluster = ClusterLocation.where(:cluster_type => 'ip_address').last
    expect(ip_cluster).not_to eq(nil)
    WeeklyStatsSummary.update_for(s2.global_id)
    summary = WeeklyStatsSummary.last
    
    expect(summary.user_id).to eq(u.id)
    data = summary.data['stats']
    expect(data['started_at']).not_to eq(nil)
    expect(data['ended_at']).not_to eq(nil)
    expect(data['devices']).not_to eq(nil)
    expect(data['locations']).not_to eq(nil)
    expect(data['all_button_counts']).not_to eq(nil)
    expect(data['all_word_counts']).not_to eq(nil)
    expect(data['total_sessions']).to eq(2)
    expect(data['total_session_seconds']).to eq(6.0)
    expect(data['total_utterance_buttons']).to eq(0.0)
    expect(data['total_utterance_words']).to eq(5.0)
    expect(data['total_utterances']).to eq(2.0)
    expect(data['days'].keys.sort).to eq(["2015-05-03", "2015-05-04", "2015-05-05", "2015-05-06", "2015-05-07", "2015-05-08", "2015-05-09"])
    expect(data['days']["2015-05-05"]['total']['total_sessions']).to eq(1)
    expect(data['days']["2015-05-05"]['total']['devices']).not_to eq(nil)
    expect(data['days']["2015-05-05"]['group_counts'].length).to eq(1)
    expect(data['days']["2015-05-05"]['group_counts'][0]['device_id']).to eq(d.global_id)
    expect(data['days']["2015-05-05"]['group_counts'][0]['geo_cluster_id']).to eq(nil)
    expect(data['days']["2015-05-05"]['group_counts'][0]['ip_cluster_id']).to eq(ip_cluster.global_id)
    expect(data['days']["2015-05-07"]['total']['total_sessions']).to eq(1)
    expect(data['days']["2015-05-07"]['total']['locations']).not_to eq(nil)
    expect(data['days']["2015-05-07"]['group_counts'].length).to eq(1)
    expect(data['days']["2015-05-07"]['group_counts'][0]['device_id']).to eq(d.global_id)
    expect(data['days']["2015-05-07"]['group_counts'][0]['geo_cluster_id']).to eq(nil)
    expect(data['days']["2015-05-07"]['group_counts'][0]['ip_cluster_id']).to eq(ip_cluster.global_id)
    expect(data['modeled_word_counts']).to eq({'ok' => 2, 'go' => 1})
    expect(data['modeled_button_counts']).to eq({'1::1_1' => {'button_id' => 1, 'board_id' => '1_1', 'text' => 'ok go ok', 'count' => 2}})
  end
  
  describe "track_for_trends" do
    it 'should collect data from all summaries for the specified weekyear' do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [
        {'type' => 'button', 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'button', 'modeling' => true, 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'button', 'modeling' => true, 'button' => {'spoken' => true, 'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'utterance', 'utterance' => {'text' => 'ok go ok', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => 1431029747}
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [
        {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => 1430856977}
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
    
      u2 = User.create
      d2 = Device.create
      s3 = LogSession.process_new({'events' => [
        {'type' => 'button', 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'button', 'modeling' => true, 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'button', 'modeling' => true, 'button' => {'spoken' => true, 'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'utterance', 'utterance' => {'text' => 'ok go ok', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => 1431029747}
      ]}, {:user => u2, :author => u2, :device => d2, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [
        {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => 1430856977}
      ]}, {:user => u2, :author => u2, :device => d2, :ip_address => '1.2.3.4'})
    
      WeeklyStatsSummary.update_for(s2.global_id)
      WeeklyStatsSummary.update_for(s4.global_id)

      summary = WeeklyStatsSummary.last
      expect(summary.weekyear).to eq(201518)
      
      sum = WeeklyStatsSummary.track_trends(201518)
      expect(sum).to_not eq(nil)
      
      expect(sum.data['totals']['total_users']).to eq(2)
      expect(sum.data['totals']['total_buttons']).to eq(6)
    end
    
    it 'should include basic totals' do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [
        {'type' => 'button', 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'button', 'modeling' => true, 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'button', 'modeling' => true, 'button' => {'spoken' => true, 'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'utterance', 'utterance' => {'text' => 'ok go ok', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => 1431029747}
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [
        {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => 1430856977}
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
          
      u2 = User.create
      d2 = Device.create
      s3 = LogSession.process_new({'events' => [
        {'type' => 'button', 'button' => {'spoken' => true, 'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'button', 'modeling' => true, 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'button', 'modeling' => true, 'button' => {'spoken' => true, 'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'utterance', 'utterance' => {'text' => 'ok go ok', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => 1431029747}
      ]}, {:user => u2, :author => u2, :device => d2, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [
        {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => 1430856977}
      ]}, {:user => u2, :author => u2, :device => d2, :ip_address => '1.2.3.4'})
    
      WeeklyStatsSummary.update_for(s2.global_id)
      WeeklyStatsSummary.update_for(s4.global_id)

      summary = WeeklyStatsSummary.last
      expect(summary.weekyear).to eq(201518)
      
      sum = WeeklyStatsSummary.track_trends(201518)
      expect(sum).to_not eq(nil)
      
      expect(sum.data['totals']['total_users']).to eq(2)
      expect(sum.data['totals']['total_modeled_words']).to eq(6)
      expect(sum.data['totals']['total_modeled_buttons']).to eq(4)
      expect(sum.data['totals']['total_words']).to eq(9)
      expect(sum.data['totals']['total_buttons']).to eq(6)
      expect(sum.data['totals']['total_core_words']).to eq(0)
    end
    
    it 'should include word counts' do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [
        {'type' => 'button', 'button' => {'spoken' => true, 'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'button', 'modeling' => true, 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'button', 'modeling' => true, 'button' => {'spoken' => true, 'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'utterance', 'utterance' => {'text' => 'ok go ok', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => 1431029747}
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [
        {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => 1430856977}
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
    
      u2 = User.create
      d2 = Device.create
      s3 = LogSession.process_new({'events' => [
        {'type' => 'button', 'button' => {'spoken' => true, 'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'button', 'modeling' => true, 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'button', 'modeling' => true, 'button' => {'spoken' => true, 'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => 1431029747 - 1},
        {'type' => 'utterance', 'utterance' => {'text' => 'ok go ok', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => 1431029747}
      ]}, {:user => u2, :author => u2, :device => d2, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [
        {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => 1430856977}
      ]}, {:user => u2, :author => u2, :device => d2, :ip_address => '1.2.3.4'})
    
      WeeklyStatsSummary.update_for(s2.global_id)
      WeeklyStatsSummary.update_for(s4.global_id)

      summary = WeeklyStatsSummary.last
      expect(summary.weekyear).to eq(201518)
      
      sum = WeeklyStatsSummary.track_trends(201518)
      expect(sum).to_not eq(nil)
      
      expect(sum.data['word_counts']).to eq({
        'ok' => 4,
        'go' => 2
      })
    end
    
    it 'should include words available in user button sets' do
      expect(WordData.standardized_words['good']).to eq(true)
      expect(WordData.standardized_words['with']).to eq(true)
      expect(WordData.standardized_words['when']).to eq(true)
      
      threes = ['me', 'me', 'that', 'that', 'baegwgaweg']
      5.times do |i|
        u = User.create
        d = Device.create(user: u)
        b = Board.create(:user => u, :settings => {
          'buttons' => [
            {'id' => '1', 'label' => 'good'},
            {'id' => '2', 'label' => 'with'},
            {'id' => '3', 'label' => threes[i]}
          ]
        })
        u.settings['preferences']['home_board'] = {'id' => b.global_id, 'key' => b.key}
        u.save
        BoardDownstreamButtonSet.update_for(b.global_id)
        s1 = LogSession.process_new({'events' => [
          {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}
        ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
        WeeklyStatsSummary.update_for(s1.global_id)
      end
      
      sum = WeeklyStatsSummary.last
      sum = WeeklyStatsSummary.track_trends(sum.weekyear)
      expect(sum).to_not eq(nil)
      expect(sum.data['available_words']['good'].length).to eq(5)
      expect(sum.data['available_words']['with'].length).to eq(5)
      expect(sum.data['available_words']['me']).to eq(nil)
      expect(sum.data['available_words']['that']).to eq(nil)
    end
    
    it 'should include only public user home board roots' do
      u = User.create
      b = Board.create(:user => u, :public => true)
      u.settings['preferences']['home_board'] = {'id' => b.global_id, 'key' => b.key}
      u.save
      s1 = LogSession.process_new({'events' => [
        {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}
      ]}, {:user => u, :author => u, :device => Device.create(:user => u), :ip_address => '1.2.3.4'})
      WeeklyStatsSummary.update_for(s1.global_id)
      
      u2 = User.create
      b2 = Board.create(:user => u2)
      u2.settings['preferences']['home_board'] = {'id' => b2.global_id, 'key' => b2.key}
      u2.save
      s2 = LogSession.process_new({'events' => [
        {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}
      ]}, {:user => u2, :author => u2, :device => Device.create(:user => u2), :ip_address => '1.2.3.4'})
      WeeklyStatsSummary.update_for(s2.global_id)
      
      5.times do |i|
        u3 = User.create
        b3 = Board.create(:user => u, :public => false, :parent_board => b)
        u3.settings['preferences']['home_board'] = {'id' => b3.global_id, 'key' => b3.key}
        u3.save
        s3 = LogSession.process_new({'events' => [
          {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}
        ]}, {:user => u3, :author => u3, :device => Device.create(:user => u3), :ip_address => '1.2.3.4'})
        WeeklyStatsSummary.update_for(s3.global_id)
        
        u4 = User.create
        b4 = Board.create(:user => u, :public => false, :parent_board => b2)
        u4.settings['preferences']['home_board'] = {'id' => b4.global_id, 'key' => b4.save}
        u4.save
        s4 = LogSession.process_new({'events' => [
          {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}
        ]}, {:user => u4, :author => u4, :device => Device.create(:user => u4), :ip_address => '1.2.3.4'})
        WeeklyStatsSummary.update_for(s4.global_id)
      end
      
      sum = WeeklyStatsSummary.last
      sum = WeeklyStatsSummary.track_trends(sum.weekyear)
      expect(sum.data['home_boards']).to_not eq({})
      expect(sum.data['home_boards'][b.key].length).to eq(6)
    end
    
    it 'should include word matches' do
      6.times do
        u = User.create
        d = Device.create
        s1 = LogSession.process_new({'events' => [
          {'type' => 'button', 'button' => {'spoken' => true, 'label' => 'this', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i - 5},
          {'type' => 'button', 'button' => {'spoken' => true, 'label' => 'that', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i - 3},
          {'type' => 'button', 'button' => {'spoken' => true, 'label' => 'then', 'button_id' => 1, 'board' => {'id' => '1_1'}}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i}
        ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
        WeeklyStatsSummary.update_for(s1.global_id)
      end
      
      sum = WeeklyStatsSummary.last
      expect(sum.data['stats']['word_pairs']).to eq({"4ef675c7908e29474e184f185134bfd6"=>{"a"=>"this", "b"=>"that", "count"=>1}, "51122eaf1983d05e75976c574d8530ef"=>{"a"=>"that", "b"=>"then", "count"=>1}})
      
      sum = WeeklyStatsSummary.track_trends(sum.weekyear)
      expect(sum.data['word_pairs']).to eq({
        "4ef675c7908e29474e184f185134bfd6"=>{"count"=>6, "a"=>"this", "b"=>"that", "user_count"=>6}, 
        "51122eaf1983d05e75976c574d8530ef"=>{"count"=>6, "a"=>"that", "b"=>"then", "user_count"=>6}
      })
    end
  end
  
  describe "trends" do
    it 'should include basic totals' do
      start = 1.month.ago.to_date
      cweek = start.cweek
      cwyear = start.cwyear
      cw1 = (cwyear * 100) + cweek
      cw2 = (cwyear * 100) + cweek + 1
      
      sum1 = WeeklyStatsSummary.create(:user_id => 0, :weekyear => cw1, :data => {
        'totals' => {
          'total_modeled_buttons' => 5,
          'total_buttons' => 8,
          'total_core_words' => 4,
          'total_words' => 14,
          'total_modeled_words' => 12,
          'total_session_seconds' => 123,
          'total_sessions' => 6
        },
        'user_ids' => ['a', 'b', 'c']
      })
      sum2 = WeeklyStatsSummary.create(:user_id => 1, :weekyear => cw1, :data => {
        'totals' => {
          'total_modeled_buttons' => 5,
          'total_buttons' => 8,
          'total_core_words' => 4,
          'total_words' => 14,
          'total_modeled_words' => 12,
          'total_session_seconds' => 123,
          'total_sessions' => 6
        },
        'user_ids' => ['a', 'b', 'c']
      })
      sum3 = WeeklyStatsSummary.create(:user_id => 0, :weekyear => cw2, :data => {
        'totals' => {
          'total_modeled_buttons' => 2,
          'total_buttons' => 11,
          'total_core_words' => 5,
          'total_words' => 18,
          'total_modeled_words' => 6,
          'total_session_seconds' => 456,
          'total_sessions' => 3
        },
        'user_ids' => ['a', 'c', 'd', 'e']
      })
      res = WeeklyStatsSummary.trends
      expect(res).to_not eq(nil)
      expect(res[:core_percent]).to eq((9.0 / (14+18).to_f).round(1) * 100.0)
      expect(res[:modeled_percent]).to eq((7.0 / (8 + 11).to_f * 2.0).round(1) / 2.0 * 100.0)
      expect(res[:total_session_seconds]).to eq(123+456)
      expect(res[:words_per_minute]).to eq(((2+12+12+6).to_f / (123+456).to_f * 60.0).round(1))
    end

    it 'should include basic totals for each week' do
      start = 1.month.ago.to_date
      cweek = start.cweek
      cwyear = start.cwyear
      cw1 = (cwyear * 100) + cweek
      cw2 = (cwyear * 100) + cweek + 1
      
      sum1 = WeeklyStatsSummary.create(:user_id => 0, :weekyear => cw1, :data => {
        'totals' => {
          'total_modeled_buttons' => 5,
          'total_buttons' => 8,
          'total_core_words' => 4,
          'total_words' => 14,
          'total_modeled_words' => 12,
          'total_session_seconds' => 123,
          'total_sessions' => 6
        },
        'user_ids' => ['a', 'b', 'c']
      })
      sum3 = WeeklyStatsSummary.create(:user_id => 0, :weekyear => cw2, :data => {
        'totals' => {
          'total_modeled_buttons' => 2,
          'total_buttons' => 11,
          'total_core_words' => 5,
          'total_words' => 18,
          'total_modeled_words' => 6,
          'total_session_seconds' => 456,
          'total_sessions' => 3
        },
        'user_ids' => ['a', 'c', 'd', 'e']
      })
      res = WeeklyStatsSummary.trends
      expect(res).to_not eq(nil)
      expect(res['weeks'][cw1]).to eq({
        'modeled_percent' => (5.0 / 8.0 * 2.0).round(1) / 2.0 * 100.0,
        'core_percent' => (4.0 / 14.0 * 2.0).round(1) / 2.0 * 100.0,
        'words_per_minute' => (14.0 / 123.0 * 60.0).round(1)
      })
      expect(res['weeks'][cw2]).to eq({
        'modeled_percent' => (2.0 / 11.0 * 2.0).round(1) / 2.0 * 100.0,
        'core_percent' => (5.0 / 18.0 * 2.0).round(1) / 2.0 * 100.0,
        'words_per_minute' => (18.0 / 456.0 * 60.0).round(1)
      })
    end
    
    it 'should not include really old trend data' do
      start = 1.month.ago.to_date
      cweek = start.cweek
      cwyear = start.cwyear
      cw1 = (cwyear * 100) + cweek
      cw2 = (cwyear * 100) + cweek + 1
      start = 4.months.ago.to_date
      cweek = start.cweek
      cwyear = start.cwyear
      cw3 = (cwyear * 100) + cweek
      
      sum1 = WeeklyStatsSummary.create(:user_id => 0, :weekyear => cw1, :data => {
        'totals' => {
          'total_modeled_buttons' => 5,
          'total_buttons' => 8,
          'total_core_words' => 4,
          'total_words' => 14,
          'total_modeled_words' => 12,
          'total_session_seconds' => 123,
          'total_sessions' => 6
        },
        'user_ids' => ['a', 'b', 'c']
      })
      sum2 = WeeklyStatsSummary.create(:user_id => 0, :weekyear => cw3, :data => {
        'totals' => {
          'total_modeled_buttons' => 5,
          'total_buttons' => 8,
          'total_core_words' => 4,
          'total_words' => 14,
          'total_modeled_words' => 12,
          'total_session_seconds' => 123,
          'total_sessions' => 6
        },
        'user_ids' => ['a', 'b', 'c']
      })
      sum3 = WeeklyStatsSummary.create(:user_id => 0, :weekyear => cw2, :data => {
        'totals' => {
          'total_modeled_buttons' => 2,
          'total_buttons' => 11,
          'total_core_words' => 5,
          'total_words' => 18,
          'total_modeled_words' => 6,
          'total_session_seconds' => 456,
          'total_sessions' => 3
        },
        'user_ids' => ['a', 'c', 'd', 'e']
      })
      res = WeeklyStatsSummary.trends
      expect(res).to_not eq(nil)
      expect(res[:core_percent]).to eq((9.0 / (14+18).to_f).round(1) * 100.0)
      expect(res[:modeled_percent]).to eq((7.0 / (8 + 11).to_f * 2.0).round(1) / 2.0 * 100.0)
      expect(res[:total_session_seconds]).to eq(123+456)
      expect(res[:words_per_minute]).to eq(((2+12+12+6).to_f / (123+456).to_f * 60.0).round(1))
      expect(res[:total_users]).to eq(nil)
      expect(res[:total_sessions]).to eq(nil)
      expect(res[:sessions_per_user]).to eq(nil)
      expect(res[:total_words]).to eq(nil)
    end
    
    it 'should include extra data for admins' do
      start = 1.month.ago.to_date
      cweek = start.cweek
      cwyear = start.cwyear
      cw1 = (cwyear * 100) + cweek
      cw2 = (cwyear * 100) + cweek + 1
      
      sum1 = WeeklyStatsSummary.create(:user_id => 0, :weekyear => cw1, :data => {
        'totals' => {
          'total_modeled_buttons' => 5,
          'total_buttons' => 8,
          'total_core_words' => 4,
          'total_words' => 14,
          'total_modeled_words' => 12,
          'total_session_seconds' => 123,
          'total_sessions' => 6
        },
        'user_ids' => ['a', 'b', 'c']
      })
      sum3 = WeeklyStatsSummary.create(:user_id => 0, :weekyear => cw2, :data => {
        'totals' => {
          'total_modeled_buttons' => 2,
          'total_buttons' => 11,
          'total_core_words' => 5,
          'total_words' => 18,
          'total_modeled_words' => 6,
          'total_session_seconds' => 456,
          'total_sessions' => 3
        },
        'user_ids' => ['a', 'c', 'd', 'e']
      })
      res = WeeklyStatsSummary.trends(true)
      expect(res).to_not eq(nil)
      expect(res[:core_percent]).to eq((9.0 / (14+18).to_f).round(1) * 100.0)
      expect(res[:modeled_percent]).to eq((7.0 / (8 + 11).to_f * 2.0).round(1) / 2.0 * 100.0)
      expect(res[:total_session_seconds]).to eq(123+456)
      expect(res[:words_per_minute]).to eq(((2+12+12+6).to_f / (123+456).to_f * 60.0).round(1))
      expect(res[:total_users]).to eq(5)
      expect(res[:total_sessions]).to eq(9)
      expect(res[:sessions_per_user]).to eq(9.0 / 5.0)
      expect(res[:total_words]).to eq(32)
    end
  end
end
