require 'spec_helper'

describe Stats do
  describe "daily summary reports" do
    it "should error if the user isn't found" do
      expect { Stats.daily_use(0, {}) }.to raise_error("user not found")
    end
    it "should return an empty result set if there are no sessions" do
      u = User.create
      start_at = 2.days.ago.utc
      end_at = Date.today.to_time.utc
      offset = Time.now.utc_offset
      res = Stats.daily_use(u.global_id, {:start_at => start_at, :end_at => end_at})
      expect(res).not_to eq(nil)
      days = res.delete(:days)
      expect(res).to eq({
        :total_sessions => 0,
        :total_utterances => 0.0,
        :words_per_utterance => 0.0,
        :buttons_per_utterance => 0.0,
        :total_buttons => 0,
        :unique_buttons => 0,
        :modeled_buttons => 0,
        :modeled_words => 0,
        :total_words => 0,
        :unique_words => 0,
        :touch_locations => {},
        :max_touches => 0,
        :words_by_frequency => [],
        :buttons_by_frequency => [],
        :words_per_minute => 0.0,
        :buttons_per_minute => 0.0,
        :utterances_per_minute => 0.0,
        :locations => [],
        :devices => [],
        :max_time_block => 0,
        :max_combined_time_block => 0,
        :max_combined_modeled_time_block => 0,
        :max_modeled_time_block => 0,
        :modeled_buttons_by_frequency => [],
        :modeled_core_words => {},
        :modeled_parts_of_speech => {},
        :modeled_time_offset_blocks => {},
        :modeled_words_by_frequency => [],
        :parts_of_speech => {},
        :parts_of_speech_combinations => {},
        :time_offset_blocks => {},
        :start_at => start_at.iso8601,
        :end_at => ((end_at.to_date + 1).to_time + offset - 1).utc.iso8601,
        :started_at => nil,
        :ended_at => nil,
        :goals => [],
        :core_words => {}
      })
      expect(days).not_to eq(nil)
      expect(days.keys.length).to eq(3)
      expect(days[days.keys[0]]).to eq({
        :total_sessions => 0,
        :buttons_by_frequency => [],
        :buttons_per_minute => 0.0,
        :buttons_per_utterance => 0.0,
        :total_buttons => 0,
        :total_utterances => 0.0,
        :total_words => 0,
        :modeled_words => 0,
        :modeled_buttons => 0,
        :unique_buttons => 0,
        :unique_words => 0,
        :utterances_per_minute => 0.0,
        :words_by_frequency => [],
        :words_per_minute => 0.0,
        :words_per_utterance => 0.0,
        :started_at => nil,
        :ended_at => nil,
        :max_time_block => 0,
        :max_combined_time_block => 0,
        :max_combined_modeled_time_block => 0,
        :max_modeled_time_block => 0,
        :modeled_buttons_by_frequency => [],
        :modeled_time_offset_blocks => {},
        :modeled_words_by_frequency => [],
        :time_offset_blocks => {},
        :goals => []
      })
    end
    
    it "should generate total reports" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ok go', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      ClusterLocation.clusterize_ips(u.global_id)
      ClusterLocation.clusterize_geos(u.global_id)
      ClusterLocation.all.each{|c| c.generate_stats(true) }
      res = Stats.daily_use(u.global_id, {:start_at => 2.days.ago, :end_at => Time.now + 100})
      expect(res[:total_utterances]).to eq(2)
      expect(res[:utterances_per_minute]).to eq(12)
      expect(res[:words_per_utterance]).to eq(2)
    end
    
    it "should default to the last six months if start and end dates aren't provided" do
      u = User.create
      res = Stats.daily_use(u.global_id, {})
      expect(res[:days].keys[-1]).to eq(Date.today.to_s)
      expect(res[:days].keys.length).to be >= 58
      expect(res[:days].keys.length).to be <= 65
    end
    
    it "should generate per-day stats" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [
        {'type' => 'button', 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i - 1},
        {'type' => 'utterance', 'utterance' => {'text' => 'ok go ok', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i}
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [
        {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => 2.days.ago.to_time.to_i}
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      ClusterLocation.clusterize_ips(u.global_id)
      ClusterLocation.clusterize_geos(u.global_id)
      ClusterLocation.all.each{|c| c.generate_stats(true) }
      res = Stats.daily_use(u.global_id, {:start_at => 3.days.ago, :end_at => Time.now + 100})
      expect(res[:total_sessions]).to eq(2)
      expect(res[:total_utterances]).to eq(2)
      expect(res[:utterances_per_minute]).to eq(20)
      expect(res[:words_per_utterance]).to eq(2.5)
      expect(res[:total_buttons]).to eq(1)
      expect(res[:total_words]).to eq(3)
      expect(res[:unique_buttons]).to eq(1)
      expect(res[:unique_words]).to eq(2)
      expect(res[:buttons_per_minute]).to eq(10)
      expect(res[:words_per_minute]).to eq(30)
      expect(res[:words_by_frequency]).to eq([
        {'text' => 'ok', 'count' => 2}, {'text' => 'go', 'count' => 1}
      ])
      expect(res[:buttons_by_frequency]).to eq([
        {'button_id' => 1, 'board_id' => '1_1', 'text' => 'ok go ok', 'count' => 1}
      ])
      
      expect(res[:days].length).to eq(4)
      day = res[:days][Date.today.to_s]
      expect(day).not_to eq(nil)
      expect(day[:total_sessions]).to eq(1)
      expect(day[:total_utterances]).to eq(1)
      expect(day[:total_buttons]).to eq(1)
      expect(day[:total_words]).to eq(3)
      expect(day[:unique_words]).to eq(2)
      expect(day[:unique_buttons]).to eq(1)
      expect(day[:words_by_frequency]).to eq([
        {'text' => 'ok', 'count' => 2}, {'text' => 'go', 'count' => 1}
      ])
      expect(day[:buttons_by_frequency]).to eq([
        {'button_id' => 1, 'board_id' => '1_1', 'text' => 'ok go ok', 'count' => 1}
      ])
      
      day = res[:days][2.days.ago.to_date.to_s]
      expect(day).not_to eq(nil)
      expect(day[:total_sessions]).to eq(1)
      expect(day[:total_utterances]).to eq(1)
      expect(day[:total_buttons]).to eq(0)
      expect(day[:total_words]).to eq(0)
      expect(day[:words_by_frequency]).to eq([])
      expect(day[:buttons_by_frequency]).to eq([])
    end

    it "should generate per-day stats when weekly summary is generated" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [
        {'type' => 'button', 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i - 1},
        {'type' => 'utterance', 'utterance' => {'text' => 'ok go ok', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i}
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [
        {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => 2.days.ago.to_time.to_i}
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      ClusterLocation.clusterize_ips(u.global_id)
      ClusterLocation.clusterize_geos(u.global_id)
      ClusterLocation.all.each{|c| c.generate_stats(true) }
      WeeklyStatsSummary.update_for(s1.global_id)
      WeeklyStatsSummary.update_for(s2.global_id)
      sum = WeeklyStatsSummary.last
      
      starty = 3.days.ago
      endy = Time.now + 100
      res = Stats.daily_use(u.global_id, {:start_at => starty, :end_at => endy})
      res = Stats.cached_daily_use(u.global_id, {:start_at => starty, :end_at => endy})
      expect(res[:cached]).to eq(true)
      expect(res[:total_sessions]).to eq(2)
      expect(res[:total_utterances]).to eq(2)
      expect(res[:utterances_per_minute]).to eq(20)
      expect(res[:words_per_utterance]).to eq(2.5)
      expect(res[:total_buttons]).to eq(1)
      expect(res[:total_words]).to eq(3)
      expect(res[:unique_buttons]).to eq(1)
      expect(res[:unique_words]).to eq(2)
      expect(res[:buttons_per_minute]).to eq(10)
      expect(res[:words_per_minute]).to eq(30)
      expect(res[:words_by_frequency]).to eq([
        {'text' => 'ok', 'count' => 2}, {'text' => 'go', 'count' => 1}
      ])
      expect(res[:buttons_by_frequency]).to eq([
        {'button_id' => 1, 'board_id' => '1_1', 'text' => 'ok go ok', 'count' => 1}
      ])
      
      expect(res[:days].length).to eq(4)
      day = res[:days][Date.today.to_s]
      expect(day).not_to eq(nil)
      expect(day[:total_sessions]).to eq(1)
      expect(day[:total_utterances]).to eq(1)
      expect(day[:total_buttons]).to eq(1)
      expect(day[:total_words]).to eq(3)
      expect(day[:unique_words]).to eq(2)
      expect(day[:unique_buttons]).to eq(1)
      expect(day[:words_by_frequency]).to eq([
        {'text' => 'ok', 'count' => 2}, {'text' => 'go', 'count' => 1}
      ])
      expect(day[:buttons_by_frequency]).to eq([
        {'button_id' => 1, 'board_id' => '1_1', 'text' => 'ok go ok', 'count' => 1}
      ])
      
      day = res[:days][2.days.ago.to_date.to_s]
      expect(day).not_to eq(nil)
      expect(day[:total_sessions]).to eq(1)
      expect(day[:total_utterances]).to eq(1)
      expect(day[:total_buttons]).to eq(0)
      expect(day[:total_words]).to eq(0)
      expect(day[:words_by_frequency]).to eq([])
      expect(day[:buttons_by_frequency]).to eq([])
    end

    it "should include sensor data in generated stats" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [
        {'type' => 'button', 'volume' => 75, 'screen_brightness' => 50, 'ambient_light' => 200, 'orientation' => {'alpha' => 355, 'beta' => 10, 'gamma' => 45, 'layout' => 'landscape-primary'}, 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i - 1},
        {'type' => 'utterance', 'volume' => 54, 'screen_brightness' => 50, 'ambient_light' => 1000, 'orientation' => {'alpha' => 90, 'beta' => 5, 'gamma' => 0, 'layout' => 'landscape-secondary'}, 'utterance' => {'text' => 'ok go ok', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i}
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [
        {'type' => 'utterance', 'volume' => 55, 'screen_brightness' => 80, 'ambient_light' => 1100, 'orientation' => {'alpha' => 95, 'beta' => 8, 'gamma' => 50, 'layout' => 'landscape-primary'}, 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => 2.days.ago.to_time.to_i}
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      ClusterLocation.clusterize_ips(u.global_id)
      ClusterLocation.clusterize_geos(u.global_id)
      ClusterLocation.all.each{|c| c.generate_stats(true) }
      WeeklyStatsSummary.update_for(s1.global_id)
      WeeklyStatsSummary.update_for(s2.global_id)
      
      starty = 3.days.ago
      endy = Time.now + 100
      res = Stats.daily_use(u.global_id, {:start_at => starty, :end_at => endy})
      res = Stats.cached_daily_use(u.global_id, {:start_at => starty, :end_at => endy})
      expect(res[:cached]).to eq(true)
      expect(res[:total_sessions]).to eq(2)
      expect(res[:total_utterances]).to eq(2)
      expect(res['volume']['average']).to eq(61.33)
      expect(res['volume']['total']).to eq(3)
      expect(res['volume']['histogram']['50-60']).to eq(2)
      expect(res['volume']['histogram']['70-80']).to eq(1)
      expect(res['screen_brightness']['average']).to eq(60)
      expect(res['screen_brightness']['total']).to eq(3)
      expect(res['screen_brightness']['histogram']['50-60']).to eq(2)
      expect(res['screen_brightness']['histogram']['80-90']).to eq(1)
      expect(res['ambient_light']['average']).to eq(766.67)
      expect(res['ambient_light']['total']).to eq(3)
      expect(res['ambient_light']['histogram']['100-250']).to eq(1)
      expect(res['ambient_light']['histogram']['1000-15000']).to eq(2)
      expect(res['orientation']['total']).to eq(3)
      expect(res['orientation']['alpha']['total']).to eq(3)
      expect(res['orientation']['alpha']['average']).to eq(180)
      expect(res['orientation']['alpha']['histogram']['N']).to eq(1)
      expect(res['orientation']['alpha']['histogram']['E']).to eq(2)
      expect(res['orientation']['beta']['total']).to eq(3)
      expect(res['orientation']['beta']['average']).to eq(7.67)
      expect(res['orientation']['beta']['histogram']['-20-20']).to eq(3)
      expect(res['orientation']['gamma']['total']).to eq(3)
      expect(res['orientation']['gamma']['average']).to eq(31.67)
      expect(res['orientation']['gamma']['histogram']['-18-18']).to eq(1)
      expect(res['orientation']['gamma']['histogram']['18-54']).to eq(2)
      
      expect(res[:days].length).to eq(4)
      day = res[:days][Date.today.to_s]
      expect(day).not_to eq(nil)
      expect(day[:total_sessions]).to eq(1)
      expect(day['volume']['average']).to eq(64.5)
      expect(day['volume']['total']).to eq(2)
      expect(day['volume']['histogram']['50-60']).to eq(1)
      expect(day['volume']['histogram']['70-80']).to eq(1)
      expect(day['screen_brightness']['average']).to eq(50)
      expect(day['screen_brightness']['total']).to eq(2)
      expect(day['screen_brightness']['histogram']['50-60']).to eq(2)
      expect(day['ambient_light']['average']).to eq(600)
      expect(day['ambient_light']['total']).to eq(2)
      expect(day['ambient_light']['histogram']['100-250']).to eq(1)
      expect(day['ambient_light']['histogram']['1000-15000']).to eq(1)
      expect(day['orientation']['total']).to eq(2)
      expect(day['orientation']['alpha']['total']).to eq(2)
      expect(day['orientation']['alpha']['average']).to eq(222.5)
      expect(day['orientation']['alpha']['histogram']['N']).to eq(1)
      expect(day['orientation']['alpha']['histogram']['E']).to eq(1)
      expect(day['orientation']['beta']['total']).to eq(2)
      expect(day['orientation']['beta']['average']).to eq(7.5)
      expect(day['orientation']['beta']['histogram']['-20-20']).to eq(2)
      expect(day['orientation']['gamma']['total']).to eq(2)
      expect(day['orientation']['gamma']['average']).to eq(22.5)
      expect(day['orientation']['gamma']['histogram']['-18-18']).to eq(1)
      expect(day['orientation']['gamma']['histogram']['18-54']).to eq(1)
      
      day = res[:days][2.days.ago.to_date.to_s]
      expect(day).not_to eq(nil)
      expect(day[:total_sessions]).to eq(1)
      expect(day['volume']['average']).to eq(55)
      expect(day['volume']['total']).to eq(1)
      expect(day['volume']['histogram']['50-60']).to eq(1)
      expect(day['screen_brightness']['average']).to eq(80)
      expect(day['screen_brightness']['total']).to eq(1)
      expect(day['screen_brightness']['histogram']['80-90']).to eq(1)
      expect(day['ambient_light']['average']).to eq(1100)
      expect(day['ambient_light']['total']).to eq(1)
      expect(day['ambient_light']['histogram']['1000-15000']).to eq(1)
      expect(day['orientation']['total']).to eq(1)
      expect(day['orientation']['alpha']['total']).to eq(1)
      expect(day['orientation']['alpha']['average']).to eq(95)
      expect(day['orientation']['alpha']['histogram']['E']).to eq(1)
      expect(day['orientation']['beta']['total']).to eq(1)
      expect(day['orientation']['beta']['average']).to eq(8)
      expect(day['orientation']['beta']['histogram']['-20-20']).to eq(1)
      expect(day['orientation']['gamma']['total']).to eq(1)
      expect(day['orientation']['gamma']['average']).to eq(50)
      expect(day['orientation']['gamma']['histogram']['18-54']).to eq(1)
    end   
    
    it "should include modeling data when available" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [
        {'type' => 'button', 'modeling' => true, 'button' => {'label' => 'donut', 'button_id' => 2, 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => Time.now.to_i - 6},
        {'type' => 'button', 'button' => {'label' => 'tastes', 'button_id' => 3, 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => Time.now.to_i - 3},
        {'type' => 'button', 'modeling' => true, 'button' => {'label' => 'ok go ok', 'button_id' => 1, 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => Time.now.to_i - 1},
        {'type' => 'utterance', 'utterance' => {'text' => 'ok go ok', 'buttons' => []}, 'timestamp' => Time.now.to_i}
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [
        {'type' => 'button', 'modeling' => true, 'button' => {'label' => 'donut', 'button_id' => 2, 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => 2.days.ago.to_time.to_i - 6},
        {'type' => 'button', 'button' => {'label' => 'tastes like', 'button_id' => 3, 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => 2.days.ago.to_time.to_i - 3},
        {'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'timestamp' => 2.days.ago.to_time.to_i}
      ]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      WeeklyStatsSummary.update_for(s1.global_id)
      WeeklyStatsSummary.update_for(s2.global_id)
      
      starty = 3.days.ago
      endy = Time.now + 100
      res = Stats.daily_use(u.global_id, {:start_at => starty, :end_at => endy})
      res = Stats.cached_daily_use(u.global_id, {:start_at => starty, :end_at => endy})
      expect(res[:cached]).to eq(true)
      expect(res[:total_sessions]).to eq(2)
      expect(res[:total_utterances]).to eq(2)
      expect(res[:total_buttons]).to eq(2)
      expect(res[:total_words]).to eq(3)
      expect(res[:modeled_buttons]).to eq(3)
      expect(res[:modeled_words]).to eq(5)
      
      expect(res[:days].length).to eq(4)
      day = res[:days][Date.today.to_s]
      expect(day).not_to eq(nil)
      expect(day[:total_sessions]).to eq(1)
      expect(day[:total_buttons]).to eq(1)
      expect(day[:total_words]).to eq(1)
      expect(day[:modeled_buttons]).to eq(2)
      expect(day[:modeled_words]).to eq(4)
      
      day = res[:days][2.days.ago.to_date.to_s]
      expect(day).not_to eq(nil)
      expect(day[:total_sessions]).to eq(1)
      expect(day[:total_buttons]).to eq(1)
      expect(day[:total_words]).to eq(2)
      expect(day[:modeled_buttons]).to eq(1)
      expect(day[:modeled_words]).to eq(1)
    end 
    
    it "should allow filtering by geolocation or ip address" do
      u = User.create
      d = Device.create
      c1 = ClusterLocation.create(:user => u, :cluster_type => 'geo', :data => {'geo' => [13, 12, 0]})
      c2 = ClusterLocation.create(:user => u, :cluster_type => 'ip_address', :data => {'ip_address' => '0000:0000:0000:0000:0000:ffff:0102:0304'})
      s1 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ok go', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ok go to the store', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'never again on my watch', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s5 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ok go again', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s6 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'never', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s7 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ice cream', 'buttons' => []}, 'geo' => ['15', '12'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s8 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'candy bar', 'buttons' => []}, 'geo' => ['15.0001', '12.0001'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      ClusterLocation.clusterize_ips(u.global_id)
      ClusterLocation.clusterize_geos(u.global_id)
      ClusterLocation.all.each{|c| c.generate_stats(true) }
      res = Stats.daily_use(u.global_id, {:start_at => 2.days.ago, :end_at => Time.now + 100, :location_id => c1.global_id})
      expect(res[:total_utterances]).to eq(6)
      expect(res[:utterances_per_minute]).to eq(12)
      expect(res[:words_per_utterance]).to eq(3)

      res = Stats.daily_use(u.global_id, {:start_at => 2.days.ago, :end_at => Time.now + 100, :location_id => c2.global_id})
      expect(res[:total_utterances]).to eq(4)
      expect(res[:utterances_per_minute]).to eq(12)
      expect(res[:words_per_utterance]).to eq(3.5)
    end
    
    it "should allow filtering to only specific devices" do
      u = User.create
      d1 = Device.create(:user => u)
      d2 = Device.create(:user => u)
      d3 = Device.create(:user => u)
      s1 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ok go', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d1, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d1, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ok go to the store', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d1, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'never again on my watch', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d1, :ip_address => '1.2.3.4'})
      s5 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ok go again', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d1, :ip_address => '1.2.3.6'})
      s6 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'never', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d2, :ip_address => '1.2.3.6'})
      s7 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ice cream', 'buttons' => []}, 'geo' => ['15', '12'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d2, :ip_address => '1.2.3.6'})
      s8 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'candy bar', 'buttons' => []}, 'geo' => ['15.0001', '12.0001'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d3, :ip_address => '1.2.3.6'})
      ClusterLocation.clusterize_ips(u.global_id)
      ClusterLocation.clusterize_geos(u.global_id)
      ClusterLocation.all.each{|c| c.generate_stats(true) }
      res = Stats.daily_use(u.global_id, {:start_at => 2.days.ago, :end_at => Time.now + 100, :device_ids => [d1.global_id]})
      expect(res[:total_utterances]).to eq(5)
      expect(res[:utterances_per_minute]).to eq(12)
      expect(res[:words_per_utterance]).to eq(3.4)

      res = Stats.daily_use(u.global_id, {:start_at => 2.days.ago, :end_at => Time.now + 100, :device_ids => [d2.global_id]})
      expect(res[:total_utterances]).to eq(2)
      expect(res[:utterances_per_minute]).to eq(12)
      expect(res[:words_per_utterance]).to eq(1.5)

      res = Stats.daily_use(u.global_id, {:start_at => 2.days.ago, :end_at => Time.now + 100, :device_ids => [d1.global_id, d2.global_id]})
      expect(res[:total_utterances]).to eq(7)
      expect(res[:utterances_per_minute]).to eq(12)
      expect(res[:words_per_utterance]).to eq(20 / 7.0)
    end
    
    it "should infer start and end dates if none provided" do
      u = User.create
      res = Stats.daily_use(u.global_id, {})
      expect(res[:days].keys[-1]).to eq(Date.today.to_s)
      expect(res[:days].keys.length).to be >= 58
      expect(res[:days].keys.length).to be <= 65
    end
    
    it "should include geo and ip-based summaries for better drill-down" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ok go', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ok go to the store', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'never again on my watch', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s5 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ok go again', 'buttons' => []}, 'geo' => ['13', '12'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s6 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'never', 'buttons' => []}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s7 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ice cream', 'buttons' => []}, 'geo' => ['15', '12'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s8 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'candy bar', 'buttons' => []}, 'geo' => ['15.0001', '12.0001'], 'timestamp' => Time.now.to_i}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      ClusterLocation.clusterize_ips(u.global_id)
      ClusterLocation.clusterize_geos(u.global_id)
      ClusterLocation.all.each{|c| c.generate_stats(true) }
      res = Stats.daily_use(u.global_id, {:start_at => 2.days.ago, :end_at => Time.now + 100})
      expect(res[:total_utterances]).to eq(8)
      
      expect(res[:locations]).not_to eq(nil)
      expect(res[:locations].length).to eq(3)
      
      geos = res[:locations].select{|l| l[:type] == 'geo' }
      expect(geos.length).to eq(1)
      expect(geos[0][:type]).to eq('geo')
      expect(geos[0][:geo]).to eq({:latitude => 13.00005, :longitude => 12.00005, :altitude => 0})
      expect(geos[0][:total_sessions]).to eq(6)
      expect(geos[0][:started_at]).to eq(s1.started_at.iso8601)
      expect(geos[0][:ended_at]).to eq(s6.ended_at.iso8601)

      ips = res[:locations].select{|l| l[:type] == 'ip_address' }.sort_by{|l| l[:readable_ip_address] }
      expect(ips.length).to eq(2)
      expect(ips[0][:type]).to eq('ip_address')
      expect(ips[0][:ip_address]).to eq("0000:0000:0000:0000:0000:ffff:0102:0304")
      expect(ips[0][:readable_ip_address]).to eq("1.2.3.4")
      expect(ips[0][:total_sessions]).to eq(4)
      expect(geos[0][:started_at]).to eq(s1.started_at.iso8601)
      expect(geos[0][:ended_at]).to eq(s4.ended_at.iso8601)

      expect(ips[1][:type]).to eq('ip_address')
      expect(ips[1][:ip_address]).to eq("0000:0000:0000:0000:0000:ffff:0102:0306")
      expect(ips[1][:readable_ip_address]).to eq("1.2.3.6")
      expect(ips[1][:total_sessions]).to eq(4)
      expect(geos[0][:started_at]).to eq(s5.started_at.iso8601)
      expect(geos[0][:ended_at]).to eq(s8.ended_at.iso8601)
    end
    
    it "should support the mechanism provided somewhere else to allow for temporarily disabling tracking for training and modelling"
    
    it "should include time blocks" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ok go', 'buttons' => []}, 'timestamp' => 1445037743}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ok go to the store', 'buttons' => []}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'never again on my watch', 'buttons' => []}, 'timestamp' => 1444994886}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      res = Stats.daily_use(u.global_id, {:start_at => Time.at(1444984571), :end_at => Time.at(1445137743)})
      
      expect(res[:time_offset_blocks]).not_to eq(nil)
      expect(res[:time_offset_blocks].keys.sort).to eq([525, 573, 581])
    end
    
    it "should include max time block value" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ok go', 'buttons' => []}, 'timestamp' => 1445037743}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'never again', 'buttons' => []}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'ok go to the store', 'buttons' => []}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'utterance', 'utterance' => {'text' => 'never again on my watch', 'buttons' => []}, 'timestamp' => 1444994886}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      res = Stats.daily_use(u.global_id, {:start_at => Time.at(1444984571), :end_at => Time.at(1445137743)})
      
      expect(res[:max_time_block]).to eq(2)
    end
    
    it "should include parts of speech" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'boy', 'spoken' => true}, 'timestamp' => 1445037743}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'hand', 'spoken' => true}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'dog', 'spoken' => true}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'run', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'cat', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'funny', 'spoken' => true}, 'timestamp' => 1444994886}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      res = Stats.daily_use(u.global_id, {:start_at => Time.at(1444984571), :end_at => Time.at(1445137743)})
      
      expect(res[:parts_of_speech]).to eq({'noun' => 4, 'verb' => 1, 'adjective' => 1})
    end

    it "should include parts of speech combinations" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'boy', 'spoken' => true}, 'timestamp' => 1445037743}, {'type' => 'button', 'button' => {'label' => 'girl', 'spoken' => true}, 'timestamp' => 1445037743}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'hand', 'spoken' => true}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'dog', 'spoken' => true}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'run', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'cat', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'funny', 'spoken' => true}, 'timestamp' => 1444994886}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      res = Stats.daily_use(u.global_id, {:start_at => Time.at(1444984571), :end_at => Time.at(1445137743)})
      
      expect(res[:parts_of_speech_combinations]).to eq({'noun,noun' => 1, 'verb,noun,adjective' => 1, 'noun,adjective' => 1})
    end
  end
  
  describe "per-day reports" do
    it "should generate a report for word/button usage based on time-of-day" do
      u = User.create
      d = Device.create
      
      ts = Time.now.utc.change(:hour => 14, :min => 30, :sec => 8).to_i
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'button_id' => '1', 'label' => 'ok go', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13', '12'], 'timestamp' => ts}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'button_id' => '2', 'label' => 'never again', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => ts + 1}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'button_id' => '3', 'label' => 'ok go to the store', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13', '12'], 'timestamp' => ts + 2}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'button_id' => '4', 'label' => 'never again on my watch', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => ts + 3}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s5 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'button_id' => '5', 'label' => 'ok go again', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13', '12'], 'timestamp' => ts + 4}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s6 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'button_id' => '6', 'label' => 'never', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => ts + 5}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s7 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'button_id' => '7', 'label' => 'ice cream', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['15', '12'], 'timestamp' => ts + 6}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s8 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'button_id' => '8', 'label' => 'candy bar', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['15.0001', '12.0001'], 'timestamp' => ts + 7}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s9 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'button_id' => '4', 'label' => 'never again on my watch', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => ts - 10808}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s10 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'button_id' => '5', 'label' => 'ok go again', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13', '12'], 'timestamp' => ts - 10808 + 1}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s11 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'button_id' => '6', 'label' => 'never', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['13.0001', '12.0001'], 'timestamp' => ts - 10808 + 2}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s12 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'button_id' => '7', 'label' => 'ice cream', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['15', '12'], 'timestamp' => ts - 10808 + 3}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      s13 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'button_id' => '8', 'label' => 'candy bar', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'geo' => ['15.0001', '12.0001'], 'timestamp' => ts - 10808 + 4}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.6'})
      ClusterLocation.clusterize_ips(u.global_id)
      ClusterLocation.clusterize_geos(u.global_id)
      ClusterLocation.all.each{|c| c.generate_stats(true) }
      start_at = Time.at(ts - 8).utc
      end_at = Time.at(ts + 13).utc

      res = Stats.hourly_use(u.global_id, {:start_at => start_at, :end_at => end_at})
      expect(res[:total_buttons]).to eq(8)
      expect(res[:total_words]).to eq(22)
      
      expect(res[:locations]).to eq(nil)
      expect(res[:hours]).not_to eq(nil)
      expect(res[:hours].length).to eq(24)
      
      expect(res[:hours].map{|h| h[:total_buttons] }).to eq([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0])
      expect(res[:hours].map{|h| h[:locations].length }).to eq([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0])
      hour = res[:hours][14]
      expect(hour[:locations].length).to eq(3)
      expect(hour[:words_by_frequency].length).to eq(14)

      start_at = Time.at(ts - 10813).utc
      end_at = Time.at(ts + 13).utc
      res = Stats.hourly_use(u.global_id, {:start_at => start_at, :end_at => end_at})
      expect(res[:total_buttons]).to eq(13)
      expect(res[:total_words]).to eq(35)
      
      expect(res[:locations]).to eq(nil)
      expect(res[:hours]).not_to eq(nil)
      expect(res[:hours].length).to eq(24)
      
      expect(res[:hours].map{|h| h[:total_buttons] }).to eq([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0])
      expect(res[:hours].map{|h| h[:buttons_by_frequency].map{|b| b['count'] }.sum }).to eq([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0])
      expect(res[:hours].map{|h| h[:words_by_frequency].map{|b| b['count'] }.sum }).to eq([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 13, 0, 0, 22, 0, 0, 0, 0, 0, 0, 0, 0, 0])
      expect(res[:hours].map{|h| h[:locations].length }).to eq([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0])
      hour = res[:hours][14]
      expect(hour[:locations].length).to eq(3)
      expect(hour[:words_by_frequency].length).to eq(14)
      hour = res[:hours][11]
      expect(hour[:locations].length).to eq(3)
      expect(hour[:words_by_frequency].length).to eq(11)
      expect(hour[:words_by_frequency].map{|w| w['text'] }).to eq(["never", "again", "watch", "on", "ok", "my", "ice", "go", "cream", "candy", "bar"])
      expect(hour[:buttons_by_frequency].map{|w| w['text'] }).to eq(["ok go again", "never again on my watch", "never", "ice cream", "candy bar"])
    end
    
    it "should include most-common words per geo/ip location per time-of-day"
    it "should allow filtering time-of-day reports by device, geo, etc."
    it "should allow drilling down into time-of-day reports"
    it "should include geo and ip-based summaries for better drill-down"
  end
  
  describe "board_use" do
    it "should fail gracefully on board not found" do
      res = Stats.board_use(nil, {})
      expect(res).not_to eq(nil)
      expect(res[:uses]).to eq(0)
    end
    
    it "should return basic board stats" do
      u = User.create
      b = Board.new(:user => u)
      expect(b).to receive(:generate_stats).and_return(nil)
      b.settings = {}
      b.settings['stars'] = 4
      b.settings['uses'] = 3
      b.settings['home_uses'] = 4
      b.settings['forks'] = 1
      b.save
      res = Stats.board_use(b.global_id, {})
      expect(res).not_to eq(nil)
      expect(res[:stars]).to eq(4)
      expect(res[:forks]).to eq(1)
      expect(res[:uses]).to eq(3)
      expect(res[:home_uses]).to eq(4)
      expect(res[:popular_forks]).to eq([])
    end
  end
  
  
  describe "lam" do
    it "should generate an empty lam file" do
      str = Stats.lam([])
      expect(str).to be_is_a(String)
      expect(str).to match(/CAUTION/)
      expect(str).to match(/2\.00/)
      expect(str.split(/\n/).length).to eql(6)
    end
    
    it "should generate with only one session" do
      s1 = LogSession.new
      s1.data = {}
      now = Time.now.to_i
      s1.data['events'] = [
        {'type' => 'button', 'button' => {'label' => 'I', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now - 10},
        {'type' => 'button', 'button' => {'label' => 'like', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now - 8},
        {'type' => 'button', 'button' => {'label' => 'ok go', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now}
      ]
      
      str = Stats.lam([s1])
      expect(str).to match(/CAUTION/)
      lines = str.split(/\n/)
      stamp = Time.at(now - 10).strftime("%H:%M:%S")
      date = Time.at(now - 10).strftime("%y-%m-%d")
      expect(lines[-4]).to eql("#{stamp} CTL *[YY-MM-DD=#{date}]*")
      expect(lines[-3]).to eql("#{stamp} SMP \"I\"")
      stamp = Time.at(now - 8).strftime("%H:%M:%S")
      expect(lines[-2]).to eql("#{stamp} SMP \"like\"")
      stamp = Time.at(now).strftime("%H:%M:%S")
      expect(lines[-1]).to eql("#{stamp} SMP \"ok go\"")
    end 
    
    it "should generate with multiple sessions" do
      s1 = LogSession.new
      s1.data = {}
      now = 1415743872
      s1.data['events'] = [
        {'type' => 'button', 'button' => {'label' => 'I', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now - 10},
        {'type' => 'button', 'button' => {'label' => 'like', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now - 8},
        {'type' => 'button', 'button' => {'label' => 'ok go', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now}
      ]
      s2 = LogSession.new
      s2.data = {}
      s2.data['events'] = [
        {'type' => 'button', 'button' => {'label' => 'do', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now + 10},
        {'type' => 'button', 'button' => {'label' => 'you', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now + 20},
        {'type' => 'button', 'button' => {'label' => 'too', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now + 22}
      ]
      
      str = Stats.lam([s1, s2])
      expect(str).to match(/CAUTION/)
      lines = str.split(/\n/)
      expect(lines[-8]).to eql("15:11:02 CTL *[YY-MM-DD=14-11-11]*")
      expect(lines[-7]).to eql("15:11:02 SMP \"I\"")
      expect(lines[-6]).to eql("15:11:04 SMP \"like\"")
      expect(lines[-5]).to eql("15:11:12 SMP \"ok go\"")
      expect(lines[-4]).to eql("15:11:22 CTL *[YY-MM-DD=14-11-11]*")
      expect(lines[-3]).to eql("15:11:22 SMP \"do\"")
      expect(lines[-2]).to eql("15:11:32 SMP \"you\"")
      expect(lines[-1]).to eql("15:11:34 SMP \"too\"")
    end
    
    it "should update the date correctly" do
      s1 = LogSession.new
      s1.data = {}
      now = 1415689201
      s1.data['events'] = [
        {'type' => 'button', 'button' => {'label' => 'I', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now - 10},
        {'type' => 'button', 'button' => {'label' => 'like', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now - 8},
        {'type' => 'button', 'button' => {'label' => 'ok go', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now}
      ]
      
      str = Stats.lam([s1])
      expect(str).to match(/CAUTION/)
      lines = str.split(/\n/)
      expect(lines[-5]).to eql("23:59:51 CTL *[YY-MM-DD=14-11-10]*")
      expect(lines[-4]).to eql("23:59:51 SMP \"I\"")
      expect(lines[-3]).to eql("23:59:53 SMP \"like\"")
      expect(lines[-2]).to eql("00:00:01 CTL *[YY-MM-DD=14-11-11]*")
      expect(lines[-1]).to eql("00:00:01 SMP \"ok go\"")
    end
    
    it "should include spelling events correctly" do
      s1 = LogSession.new
      s1.data = {}
      now = 1415743872
      s1.data['events'] = [
        {'type' => 'button', 'button' => {'label' => 'd', 'vocalization' => '+d', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now - 10},
        {'type' => 'button', 'button' => {'label' => 'o', 'vocalization' => '+o', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now - 8},
        {'type' => 'button', 'button' => {'label' => 'g', 'vocalization' => '+g', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now}
      ]
      
      str = Stats.lam([s1])
      expect(str).to match(/CAUTION/)
      lines = str.split(/\n/)
      expect(lines[-4]).to eql("15:11:02 CTL *[YY-MM-DD=14-11-11]*")
      expect(lines[-3]).to eql("15:11:02 SPE \"d\"")
      expect(lines[-2]).to eql("15:11:04 SPE \"o\"")
      expect(lines[-1]).to eql("15:11:12 SPE \"g\"")
    end
    
    it "should include word completion events correctly" do
      s1 = LogSession.new
      s1.data = {}
      now = 1415743872
      s1.data['events'] = [
        {'type' => 'button', 'button' => {'label' => 'd', 'vocalization' => '+d', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now - 10},
        {'type' => 'button', 'button' => {'label' => 'o', 'vocalization' => '+o', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now - 8},
        {'type' => 'button', 'button' => {'completion' => 'dog', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now}
      ]
      
      str = Stats.lam([s1])
      expect(str).to match(/CAUTION/)
      lines = str.split(/\n/)
      expect(lines[-4]).to eql("15:11:02 CTL *[YY-MM-DD=14-11-11]*")
      expect(lines[-3]).to eql("15:11:02 SPE \"d\"")
      expect(lines[-2]).to eql("15:11:04 SPE \"o\"")
      expect(lines[-1]).to eql("15:11:12 WPR \"dog\"")
    end
    
    it "should ignore extra events" do
      s1 = LogSession.new
      s1.data = {}
      now = 1415743872
      s1.data['events'] = [
        {'type' => 'button', 'button' => {'label' => 'cat', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now - 10},
        {'type' => 'button', 'button' => {'label' => '+s', 'vocalization' => ':plural', 'board' => {'id' => '1_1'}, 'spoken' => true}, 'timestamp' => now - 8},
        {'type' => 'action', 'action' => {'action' => 'open_board'}, 'timestamp' => now},
        {'type' => 'utterance', 'utterance' => {'sentence' => 'good things are happening'}, 'timestamp' => now}
      ]
      
      str = Stats.lam([s1])
      expect(str).to match(/CAUTION/)
      lines = str.split(/\n/)
      expect(lines[-2]).to eql("15:11:02 CTL *[YY-MM-DD=14-11-11]*")
      expect(lines[-1]).to eql("15:11:02 SMP \"cat\"")
    end
  end
  
  describe "time_block" do
    it "should properly adjust a timestamp to the right time block" do
      expect(Stats.time_block(0)).to eq(4 * 24 * 4)
      expect(Stats.time_block(Date.parse('monday').to_time(:utc).to_i)).to eq(4 * 24 * 1)
      expect(Stats.time_block(Date.parse('friday').to_time(:utc).to_i)).to eq(4 * 24 * 5)
      expect(Stats.time_block(1445125716)).to eq(671)
    end
  end
  
  describe "time_offset_blocks" do
    it "should generate a list of blocks from a list" do
      blocks = {}
      blocks[1445125716 / 15] = 4
      blocks[1444521012 / 15] = 2
      blocks[0] = 2
      blocks[Date.parse('tuesday').to_time(:utc).to_i / 15] = 3
      blocks[Date.parse('monday').to_time(:utc).to_i / 15] = 1
      
      res = Stats.time_offset_blocks(blocks)
      expect(res.keys.length).to eq(4)
      expect(res[96]).to eq(1)
      expect(res[671]).to eq(6)
      expect(res[384]).to eq(2)
      expect(res[192]).to eq(3)
    end
  end
  
  describe "time_block_use_for_sessions" do
    it "should generate a list of timed_blocks chunked by the specified interval" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'boy', 'spoken' => true}, 'timestamp' => 1445037743}, {'type' => 'button', 'button' => {'label' => 'girl', 'spoken' => true}, 'timestamp' => 1445037743.1}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'hand', 'spoken' => true}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'dog', 'spoken' => true}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'run', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'cat', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'funny', 'spoken' => true}, 'timestamp' => 1444994886}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      res = Stats.time_block_use_for_sessions([s1, s2, s3, s4])
      expect(res[:timed_blocks]).not_to eq(nil)
      expect(res[:timed_blocks][1445037743 / 15]).to eq(2)
      expect(res[:timed_blocks][1445044954 / 15]).to eq(1)
      expect(res[:timed_blocks][1444994571 / 15]).to eq(1)
      expect(res[:timed_blocks][1444994886 / 15]).to eq(3)
      expect(res[:max_time_block]).to eq(3)
    end
  end
  
  describe "parts_of_speech_stats" do
    it "should combine all parts_of_speech values" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'boy', 'spoken' => true}, 'timestamp' => 1445037743}, {'type' => 'button', 'button' => {'label' => 'girl', 'spoken' => true}, 'timestamp' => 1445037743}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'hand', 'spoken' => true}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'dog', 'spoken' => true}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'run', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'cat', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'funny', 'spoken' => true}, 'timestamp' => 1444994886}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      res = Stats.parts_of_speech_stats([s1, s2, s3, s4])
      expect(res[:parts_of_speech]).not_to eq(nil)
      expect(res[:parts_of_speech]).to eq({'noun' => 5, 'verb' => 1, 'adjective' => 1})
      expect(res[:parts_of_speech_combinations]).not_to eq(nil)
    end
    
    it "should create parts_of_speech 2-step and 3-step sequences" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'boy', 'spoken' => true}, 'timestamp' => 1445037743}, {'type' => 'button', 'button' => {'label' => 'girl', 'spoken' => true}, 'timestamp' => 1445037743}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'hand', 'spoken' => true}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'dog', 'spoken' => true}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'run', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'cat', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'funny', 'spoken' => true}, 'timestamp' => 1444994886}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      res = Stats.parts_of_speech_stats([s1, s2, s3, s4])
      expect(res[:parts_of_speech_combinations]).to eq({'noun,noun' => 1, 'verb,noun,adjective' => 1, 'noun,adjective' => 1})
    end
    
    it "should not create multi-step sequences across a clear action" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'boy', 'spoken' => true}, 'timestamp' => 1445037743}, {'type' => 'button', 'button' => {'label' => 'girl', 'spoken' => true}, 'timestamp' => 1445037744}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'hand', 'spoken' => true}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'dog', 'spoken' => true}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'run', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'cat', 'spoken' => true}, 'timestamp' => 1444994887}, {'type' => 'action', 'action' => 'clear', 'timestamp' => 1444994888}, {'type' => 'button', 'button' => {'label' => 'funny', 'spoken' => true}, 'timestamp' => 1444994889}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      res = Stats.parts_of_speech_stats([s1, s2, s3, s4])
      expect(res[:parts_of_speech_combinations]).to eq({'noun,noun' => 1, 'verb,noun' => 1})
    end
    
    it "should not create multi-step sequences across a vocalize action" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'boy', 'spoken' => true}, 'timestamp' => 1445037743}, {'type' => 'button', 'button' => {'label' => 'girl', 'spoken' => true}, 'timestamp' => 1445037744}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'hand', 'spoken' => true}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'dog', 'spoken' => true}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'run', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'cat', 'spoken' => true}, 'timestamp' => 1444994887}, {'type' => 'utterance', 'utterance' => {'text' => 'ok cool'}, 'timestamp' => 1444994888}, {'type' => 'button', 'button' => {'label' => 'funny', 'spoken' => true}, 'timestamp' => 1444994889}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      res = Stats.parts_of_speech_stats([s1, s2, s3, s4])
      expect(res[:parts_of_speech_combinations]).to eq({'noun,noun' => 1, 'verb,noun' => 1})
    end
    
    it "should create consecutive mutli-step sequences" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'boy', 'spoken' => true}, 'timestamp' => 1445037743}, {'type' => 'button', 'button' => {'label' => 'girl', 'spoken' => true}, 'timestamp' => 1445037743}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'hand', 'spoken' => true}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'dog', 'spoken' => true}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'run', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'cat', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'funny', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'ugly', 'spoken' => true}, 'timestamp' => 1444994887}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      res = Stats.parts_of_speech_stats([s1, s2, s3, s4])
      expect(res[:parts_of_speech_combinations]).to eq({'noun,noun' => 1, 'verb,noun,adjective' => 1, 'noun,adjective,adjective' => 1, 'adjective,adjective' => 1})
    end
    
    it "should handle spelling within sequences" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'boy', 'spoken' => true}, 'timestamp' => 1445037743}, {'type' => 'button', 'button' => {'label' => 'girl', 'spoken' => true}, 'timestamp' => 1445037744}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'hand', 'spoken' => true}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'dog', 'spoken' => true}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      events = [
        {'type' => 'button', 'button' => {'label' => 'run'}, 'timestamp' => 1444994881}, 
        {'type' => 'button', 'button' => {'label' => 'f', 'vocalization' => '+f'}, 'timestamp' => 1444994883},
        {'type' => 'button', 'button' => {'label' => 'u', 'vocalization' => '+u'}, 'timestamp' => 1444994884},
        {'type' => 'button', 'button' => {'label' => 'n', 'vocalization' => '+n'}, 'timestamp' => 1444994885},
        {'type' => 'button', 'button' => {'label' => 'n', 'vocalization' => '+n'}, 'timestamp' => 1444994886},
        {'type' => 'button', 'button' => {'label' => 'y', 'vocalization' => '+y'}, 'timestamp' => 1444994887},
        {'type' => 'button', 'button' => {'label' => ' ', 'vocalization' => ':space', 'completion' => 'funny'}, 'timestamp' => 1444994888},
        {'type' => 'button', 'button' => {'label' => 'cat'}, 'timestamp' => 1444994889}, 
      ]
      s4 = LogSession.process_new({'events' => events}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      res = Stats.parts_of_speech_stats([s1, s2, s3, s4])
      expect(res[:parts_of_speech_combinations]).to eq({'noun,noun' => 1, 'verb,adjective,noun' => 1, 'adjective,noun' => 1})
    end
    
    it "should handle spelling at the end of a sequence" do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'boy', 'spoken' => true}, 'timestamp' => 1445037743}, {'type' => 'button', 'button' => {'label' => 'girl', 'spoken' => true}, 'timestamp' => 1445037744}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'hand', 'spoken' => true}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'dog', 'spoken' => true}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      events = [
        {'type' => 'button', 'button' => {'label' => 'run', 'spoken' => true}, 'timestamp' => 1444994881}, 
        {'type' => 'button', 'button' => {'label' => 'cat', 'spoken' => true}, 'timestamp' => 1444994882}, 
        {'type' => 'button', 'button' => {'label' => 'f', 'vocalization' => '+f'}, 'timestamp' => 1444994883},
        {'type' => 'button', 'button' => {'label' => 'u', 'vocalization' => '+u'}, 'timestamp' => 1444994884},
        {'type' => 'button', 'button' => {'label' => 'n', 'vocalization' => '+n'}, 'timestamp' => 1444994885},
        {'type' => 'button', 'button' => {'label' => 'n', 'vocalization' => '+n'}, 'timestamp' => 1444994886},
        {'type' => 'button', 'button' => {'label' => 'y', 'vocalization' => '+y'}, 'timestamp' => 1444994887},
      ]
      s4 = LogSession.process_new({'events' => events}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      res = Stats.parts_of_speech_stats([s1, s2, s3, s4])
      expect(res[:parts_of_speech_combinations]).to eq({'noun,noun' => 1, 'verb,noun,adjective' => 1, 'noun,adjective' => 1})
    end
  end

  describe "process_lam" do
    it "should not error on bad data" do
      res = Stats.process_lam("", nil)
      expect(res).to eq([])
      res = Stats.process_lam("asdf\n12345", nil)
      expect(res).to eq([])
    end
    
    it "should process valid data" do
      u = User.create
      res = Stats.process_lam(%{
      EXTRA JUNK
SOME SILLY GARBAGE
11:00:00 SPE "something cool"
15:11:22 WPR "something else"
18:01:55 SMP "something again"
19:00:00 CTL *[YY-MM-DD=16-07-13]*
02:01:05 SMP "somebody else"
      }, u)
      expect(res.length).to eq(4)
    end
    
    it "should return an events list" do
      u = User.create
      res = Stats.process_lam(%{
      EXTRA JUNK
SOME SILLY GARBAGE
11:00:00 SPE "something cool"
15:11:22 WPR "something else"
18:01:55 SMP "something again"
19:00:00 CTL *[YY-MM-DD=16-07-13]*
02:01:05 SMP "somebody else"
      }, u)
      expect(res.length).to eq(4)
      expect(res[0]['type']).to eq('button')
      expect(res[0]['button']['label']).to eq('something cool')
      expect(res[1]['type']).to eq('button')
      expect(res[1]['button']['label']).to eq('something else')
      expect(res[2]['type']).to eq('button')
      expect(res[2]['button']['label']).to eq('something again')
      expect(res[3]['type']).to eq('button')
      expect(res[3]['button']['label']).to eq('somebody else')
    end
    
    it "should use the date information provided" do
      u = User.create
      res = Stats.process_lam(%{
      EXTRA JUNK
SOME SILLY GARBAGE
11:00:00 SPE "something cool"
15:11:22 WPR "something else"
18:01:55 SMP "something again"
19:00:00 CTL *[YY-MM-DD=16-07-13]*
02:01:05 SMP "somebody else"
      }, u)
      expect(res.length).to eq(4)
      expect(res[0]['type']).to eq('button')
      expect(res[0]['button']['label']).to eq('something cool')
      expect(res[0]['timestamp']).to eq(Time.now.change(:hour => 11, :min => 0, :sec => 0).to_i)
      expect(res[1]['type']).to eq('button')
      expect(res[1]['button']['label']).to eq('something else')
      expect(res[1]['timestamp']).to eq(Time.now.change(:hour => 15, :min => 11, :sec => 22).to_i)
      expect(res[2]['type']).to eq('button')
      expect(res[2]['button']['label']).to eq('something again')
      expect(res[2]['timestamp']).to eq(Time.now.change(:hour => 18, :min => 1, :sec => 55).to_i)
      expect(res[3]['type']).to eq('button')
      expect(res[3]['button']['label']).to eq('somebody else')
      expect(res[3]['timestamp']).to eq(1468396865)
    end
  end
  
  describe "word_pairs" do
    it 'should generate a list of pairs' do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'good', 'spoken' => true}, 'timestamp' => 1445037743}, {'type' => 'button', 'button' => {'label' => 'we', 'spoken' => true}, 'timestamp' => 1445037743}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'bad', 'spoken' => true}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'up', 'spoken' => true}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'down', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'this', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'when', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'like', 'spoken' => true}, 'timestamp' => 1444994887}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      res = Stats.word_pairs([s1, s2, s3, s4])
      expect(res).to eq({
        "64b4232e689544e3f19e510306caaca8" => {"a"=>"this", "b"=>"when", "count"=>1},
        "774b25a0bbd018d13ab37d517f461444" => {"a"=>"when", "b"=>"like", "count"=>1},
        "77b9476cebc127e4da5785a1d98f6dd6" => {"a"=>"down", "b"=>"this", "count"=>1},
        "af956f01857e752ae09e4f1c433940dc" => {"a"=>"good", "b"=>"we", "count"=>1},
      })
    end
    
    it 'should not include pairs over too long a delay' do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'good', 'spoken' => true}, 'timestamp' => 1445037743}, {'type' => 'button', 'button' => {'label' => 'we', 'spoken' => true}, 'timestamp' => 1445037743}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'bad', 'spoken' => true}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'up', 'spoken' => true}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'down', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'this', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'blech', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'like', 'spoken' => true}, 'timestamp' => 1444994887}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      res = Stats.word_pairs([s1, s2, s3, s4])
      expect(res).to eq({"af956f01857e752ae09e4f1c433940dc"=>{"a"=>"good", "b"=>"we", "count"=>1}, "77b9476cebc127e4da5785a1d98f6dd6"=>{"a"=>"down", "b"=>"this", "count"=>1}})
    end
    
    it 'should not include pairs where one is not a valid key' do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'down', 'spoken' => true}, 'timestamp' => 1445037743}, {'type' => 'button', 'button' => {'label' => 'this', 'spoken' => true}, 'timestamp' => 1445037743}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'bad', 'spoken' => true}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'up', 'spoken' => true}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'down', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'this', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'blech', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'like', 'spoken' => true}, 'timestamp' => 1444994887}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      res = Stats.word_pairs([s1, s2, s3, s4])
      expect(res).to eq({"77b9476cebc127e4da5785a1d98f6dd6"=>{"a"=>"down", "b"=>"this", "count"=>2}})
    end
    
    it 'should not include two valid words with an invalid one in the middle' do
      u = User.create
      d = Device.create
      s1 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'good', 'spoken' => true}, 'timestamp' => 1445037743}, {'type' => 'button', 'button' => {'label' => 'we', 'spoken' => true}, 'timestamp' => 1445037743}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s2 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'bad', 'spoken' => true}, 'timestamp' => 1445044954}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s3 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'up', 'spoken' => true}, 'timestamp' => 1444994571}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      s4 = LogSession.process_new({'events' => [{'type' => 'button', 'button' => {'label' => 'down', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'this', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'blech', 'spoken' => true}, 'timestamp' => 1444994886}, {'type' => 'button', 'button' => {'label' => 'like', 'spoken' => true}, 'timestamp' => 1444994887}]}, {:user => u, :author => u, :device => d, :ip_address => '1.2.3.4'})
      
      res = Stats.word_pairs([s1, s2, s3, s4])
      expect(res).to eq({"af956f01857e752ae09e4f1c433940dc"=>{"a"=>"good", "b"=>"we", "count"=>1}, "77b9476cebc127e4da5785a1d98f6dd6"=>{"a"=>"down", "b"=>"this", "count"=>1}})
    end
  end
end
