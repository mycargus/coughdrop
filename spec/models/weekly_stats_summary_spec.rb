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
end
