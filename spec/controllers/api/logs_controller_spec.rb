require 'spec_helper'

describe Api::LogsController, :type => :controller do
  describe "index" do
    it "should require api token" do
      get :index
      assert_missing_token
    end
    
    it "should return unauthorized unless edit permissions allowed" do
      u = User.create
      token_user
      get :index, params: {:user_id => u.global_id}
      assert_unauthorized
    end
    
    it "should return a list of logs" do
      token_user
      LogSession.process_new({
        :events => [
          {'timestamp' => 4.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
          {'timestamp' => 3.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => @user, :device => @device, :author => @user})
      get :index, params: {:user_id => @user.global_id}
      json = JSON.parse(response.body)
      expect(json['log'].length).to eq(1)
    end
    
    it "should paginate long results" do
      token_user
      (JsonApi::Log::DEFAULT_PAGE + 1).times do |i|
        LogSession.process_new({
          :events => [
            {'timestamp' => i.days.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
            {'timestamp' => (i.days.ago + 10).to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
          ]
        }, {:user => @user, :device => @device, :author => @user})
      end
      get :index, params: {:user_id => @user.global_id}
      json = JSON.parse(response.body)
      expect(json['log'].length).to eq(JsonApi::Log::DEFAULT_PAGE)
      expect(json['meta']['next_url']).not_to eq(nil)
    end
    
    it "should return supervisee sessions when requested" do
      users = [User.create, User.create, User.create]
      token_user
      users.each_with_index do |u, idx|
        User.link_supervisor_to_user(@user, u) unless idx == 2
        d = Device.create(:user => u)
        3.times do |i|
          LogSession.process_new({
            :events => [
              {'timestamp' => (i.days.ago + i).to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
              {'timestamp' => (i.days.ago + 100).to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
            ]
          }, {:user => u, :device => d, :author => u})
        end
      end
      Worker.process_queues
      expect(@user.reload.supervisees.length).to eq(2)
      get :index, params: {:user_id => @user.global_id, :supervisees => true}
      json = JSON.parse(response.body)
      logs = json['log'].sort_by{|l| l['id'] }
      expect(logs.length).to eq(6)
      expect(logs.map{|l| l['author']['id'] }.sort).to eq([users[0].global_id, users[0].global_id, users[0].global_id, users[1].global_id, users[1].global_id, users[1].global_id])
      expect(json['meta']['next_url']).to eq(nil)
    end
    
    it "should filter by query parameters" do
      token_user
      geo = ClusterLocation.create(:user => @user, :cluster_type => 'geo')
      ip = ClusterLocation.create(:user => @user, :cluster_type => 'ip_address')
      l1 = LogSession.process_new({
        :events => [
          {'timestamp' => 3.weeks.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => @user, :device => @device, :author => @user})
      l1.geo_cluster_id = geo.id
      l1.ip_cluster_id = ip.id
      l1.save
      l2 = LogSession.process_new({
        :events => [
          {'timestamp' => 1.week.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => @user, :device => @device, :author => @user})
      l2.geo_cluster_id = geo.id
      l2.save
      l3 = LogSession.process_new({
        :events => [
          {'timestamp' => 1.day.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => @user, :device => @device, :author => @user})
      l3.ip_cluster_id = ip.id
      l3.save 

      get :index, params: {:user_id => @user.global_id, :start => 2.weeks.ago.to_s, :end => 1.day.from_now.to_s, :device_id => @device.global_id}
      json = JSON.parse(response.body)
      expect(json['log'].length).to eq(2)
      expect(json['log'].map{|l| l['id'] }).to eq([l3.global_id, l2.global_id])
      
      get :index, params: {:user_id => @user.global_id, :device_id => "abc"}
      json = JSON.parse(response.body)
      expect(json['log'].length).to eq(0)

      get :index, params: {:user_id => @user.global_id, :end => 3.days.ago.to_s}
      json = JSON.parse(response.body)
      expect(json['log'].length).to eq(2)
      expect(json['log'].map{|l| l['id'] }).to eq([l2.global_id, l1.global_id])

      get :index, params: {:user_id => @user.global_id, :location_id => geo.global_id}
      json = JSON.parse(response.body)
      expect(json['log'].length).to eq(2)
      expect(json['log'].map{|l| l['id'] }).to eq([l2.global_id, l1.global_id])

      get :index, params: {:user_id => @user.global_id, :location_id => ip.global_id}
      json = JSON.parse(response.body)
      expect(json['log'].length).to eq(2)
      expect(json['log'].map{|l| l['id'] }).to eq([l3.global_id, l1.global_id])
    end
    
    it "should include query parameters in api next_url" do
      token_user
      (JsonApi::Log::DEFAULT_PAGE + 1).times do |i|
        LogSession.process_new({
          :events => [
            {'timestamp' => i.days.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
            {'timestamp' => (i.days.ago + 10).to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
          ]
        }, {:user => @user, :device => @device, :author => @user})
      end
      get :index, params: {:user_id => @user.global_id, :start => 2.weeks.ago.to_s}
      json = JSON.parse(response.body)
      expect(json['log'].length).to eq(JsonApi::Log::DEFAULT_PAGE)
      expect(json['meta']['next_url']).to match(/user_id=/)
      expect(json['meta']['next_url']).to match(/start=/)
      expect(json['meta']['next_url']).not_to match(/end=/)
      expect(json['meta']['next_url']).not_to match(/device_id=/)
      expect(json['meta']['next_url']).not_to match(/location_id=/)
    end

    it "should filter by goal_id" do
      token_user
      g = UserGoal.create(:user => @user)
      LogSession.process_new({
        :goal_id => g.global_id,
        :events => [
          {'timestamp' => 4.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
          {'timestamp' => 3.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => @user, :device => @device, :author => @user})
      LogSession.process_new({
        :goal_id => g.global_id,
        :events => [
          {'timestamp' => 8.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
          {'timestamp' => 7.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => @user, :device => @device, :author => @user})
      LogSession.process_new({
        :goal_id => g.global_id,
        :events => [
          {'timestamp' => 18.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
          {'timestamp' => 17.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => @user, :device => @device, :author => @user})
      get :index, params: {:user_id => @user.global_id, :goal_id => g.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['log'].length).to eq(3)
    end
    
    it "should return nothing for goal_id that doesn't match user" do
      token_user
      u = User.create
      g = UserGoal.create(:user => u)
      
      LogSession.process_new({
        :goal_id => g.global_id,
        :events => [
          {'timestamp' => 4.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
          {'timestamp' => 3.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => u, :device => @device, :author => @user})
      LogSession.process_new({
        :goal_id => g.global_id,
        :events => [
          {'timestamp' => 8.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
          {'timestamp' => 7.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => u, :device => @device, :author => @user})
      LogSession.process_new({
        :goal_id => g.global_id,
        :events => [
          {'timestamp' => 18.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
          {'timestamp' => 17.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => u, :device => @device, :author => @user})

      get :index, params: {:user_id => @user.global_id, :goal_id => g.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['log'].length).to eq(0)
    end
  end

  
  describe "create" do
    it "should require api token" do
      post :create, params: {}
      assert_missing_token
    end
    
    it "should return unauthorized unless edit permissions allowed" do
      u = User.create
      token_user
      post :create, params: {:user_id => u.global_id}
      assert_unauthorized
    end
    
    it "should generate a log result and return it" do
      token_user
      post :create, params: {:log => {:events => [{'user_id' => @user.global_id, 'timestamp' => 5.hours.ago.to_i, 'type' => 'button', 'button' => {'label' => 'cool', 'board' => {'id' => '1_1'}}}]}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['log']['pending']).to eq(true)
      Worker.process_queues
      log = LogSession.last
      expect(log.data['event_summary']).to eq('cool')
    end

    it "should try to extract and canonicalize the ip address" do
      token_user
      request.env['HTTP_X_FORWARDED_FOR'] = "8.7.6.5"
      post :create, params: {:log => {:events => [{'user_id' => @user.global_id, 'timestamp' => 5.hours.ago.to_i, 'type' => 'button', 'button' => {'label' => 'cool', 'board' => {'id' => '1_1'}}}]}}
      expect(response).to be_success
      Worker.process_queues
      s = LogSession.last
      json = JSON.parse(response.body)
      expect(json['log']['pending']).to eq(true)
      expect(s.data['event_summary']).to eq('cool')
      expect(s.data['ip_address']).to eq("0000:0000:0000:0000:0000:ffff:0807:0605")
    end
    
    it "should error gracefully on log update fail" do
      expect_any_instance_of(LogSession).to receive(:process_params){|u| u.add_processing_error("bacon") }.and_return(false)
      token_user
      post :create, params: {:log => {:events => [{'user_id' => @user.global_id, 'timestamp' => 5.hours.ago.to_i, 'type' => 'button', 'button' => {'label' => 'cool', 'board' => {'id' => '1_1'}}}]}}
      Worker.process_queues
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['log']['pending']).to eql(true)
    end
    
    it "should attach a note to a goal" do
      token_user
      g = UserGoal.create(:user => @user)
      post :create, params: {:log => {
        'note' => {
          'text' => 'ahem',
          'timestamp' => 1431461182
        },
        'goal_id' => g.global_id
      }}
      expect(response).to be_success
      json = JSON.parse(response.body)
      Worker.process_queues
      log = LogSession.last
      expect(log.data['event_summary']).to eq('Note by no-name: ahem')
      expect(log.goal).to eq(g)
      expect(log.log_type).to eq('note')
    end
    
    it "should ignore the goal_id when attaching a note to a goal if invalid" do
      token_user
      g = UserGoal.create(:user => @user)
      post :create, params: {:log => {
        'note' => {
          'text' => 'ahem',
          'timestamp' => 1431461182
        },
        'goal_id' => '12345'
      }}
      expect(response).to be_success
      json = JSON.parse(response.body)
      Worker.process_queues
      log = LogSession.last
      expect(log.data['event_summary']).to eq('Note by no-name: ahem')
      expect(log.goal).to eq(nil)
      expect(log.log_type).to eq('note')
    end
  end
  
  describe "update" do
    it "should require api token" do
      put 'update', params: {:id => '1234'}
      assert_missing_token
    end
    
    it "should require permission" do
      token_user
      u = User.create
      d = Device.create(:user => u)
      log = LogSession.create(:user => u, :author => u, :device => d)
      put 'update', params: {:id => log.global_id}
      assert_unauthorized
    end
    
    it "should call process with :update_only flag" do
      token_user
      d = Device.create(:user => @user)
      log = LogSession.create(:user => @user, :author => @user, :device => d)
      expect_any_instance_of(LogSession).to receive(:process_params).with({}, hash_including(:update_only => true))
      put 'update', params: {:id => log.global_id, 'log' => {}}
      expect(response).to be_success
    end
    
    it "should update notes" do
      token_user
      d = Device.create(:user => @user)
      now = 1415689201
      params = {
        'events' => [
          {'id' => 'abc', 'type' => 'button', 'button' => {'label' => 'I', 'board' => {'id' => '1_1'}}, 'timestamp' => now - 10, },
          {'id' => 'qwe', 'type' => 'button', 'button' => {'label' => 'like', 'board' => {'id' => '1_1'}}, 'timestamp' => now - 8},
          {'id' => 'wer', 'type' => 'button', 'button' => {'label' => 'ok go', 'board' => {'id' => '1_1'}}, 'timestamp' => now}
        ]
      }
      log = LogSession.process_new(params, {
        :user => @user,
        :author => @user,
        :device => d
      })
      expect(log.data['events'].map{|e| e['id'] }).to eql(['abc', 'qwe', 'wer'])
      expect(log.data['events'].map{|e| e['notes'] }).to eql([nil, nil, nil])
      
      params = {
        'events' => [
          {'id' => 'abc', 'type' => 'button', 'button' => {'label' => 'I', 'board' => {'id' => '1_1'}}, 'timestamp' => now - 10, 'notes' => [
            {'note' => 'ok cool'}
          ]},
          {'id' => 'qwe', 'type' => 'button', 'button' => {'label' => 'like', 'board' => {'id' => '1_1'}}, 'timestamp' => now - 8},
          {'id' => 'wer', 'type' => 'button', 'button' => {'label' => 'ok go', 'board' => {'id' => '1_1'}}, 'timestamp' => now, 'notes' => [
            {'note' => 'that is good'}
          ]}
        ]
      }
      put 'update', params: {:id => log.global_id, 'log' => params}
      expect(response).to be_success
      json = JSON.parse(response.body)
      
      expect(json['log']['events'].length).to eql(3)

      notes = json['log']['events'][0]['notes']
      expect(notes.length).to eql(1);
      note = notes[0]
      expect(note['note']).to eql('ok cool')
      expect(note['author']).to eql({
        'id' => @user.global_id,
        'user_name' => @user.user_name
      })

      note = json['log']['events'][2]['notes'][0]
      expect(note['note']).to eql('that is good')
      expect(note['author']).to eql({
        'id' => @user.global_id,
        'user_name' => @user.user_name
      })
    end
  end
  
  describe "lam" do
    it "should not require api token" do
      get 'lam', params: {:log_id => '1234'}
      expect(response).to be_success
    end
    
    it "should error gracefully on not found" do
      get 'lam', params: {:log_id => '1234'}
      expect(response).to be_success
      expect(response.body).to eql("Not found")
      
      u = User.create
      d = Device.create
      log = LogSession.create(:user => u, :device => d, :author => u)
      get 'lam', params: {:log_id => log.global_id}
      expect(response).to be_success
      expect(response.body).to eql("Not found")
    end
    
    it "should render a LAM file on success" do
      u = User.create
      d = Device.create
      log = LogSession.create(:user => u, :device => d, :author => u)
      get 'lam', params: {:log_id => log.global_id, :nonce => log.data['nonce']}
      expect(response).to be_success
      expect(response.body).to match(/CAUTION/)
      expect(response.body).to match(/LAM Version 2\.00/)
    end
  end

  describe "import" do
    it "should require an api token" do
      post 'import', params: {:user_id => 'asdf'}
      assert_missing_token
    end
    
    it "should error if the user doesn't exist" do
      token_user
      post 'import', params: {:user_id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      u = User.create
      post 'import', params: {:user_id => u.global_id}
      assert_unauthorized
    end
    
    it "should error if no content provided" do
      token_user
      post 'import', params: {:user_id => @user.global_id}
      expect(response).to_not be_success
      json = JSON.parse(response.body)
      expect(json['error']).to eq('missing content for import')
    end
    
    it "should process the data" do
      token_user
      expect(Stats).to receive(:process_lam).with('some content', @user).and_return([{}])
      post 'import', params: {:user_id => @user.global_id, :content => "some content"}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['log']).to_not eq(nil)
    end

    it "should import obl data"
  end
  
  describe "trends" do
    it "should not require an api token" do
      expect(Permissable.permissions_redis).to receive(:get).and_return(nil)
      expect(WeeklyStatsSummary).to receive(:trends).with(false).and_return({a: 1})
      get 'trends'
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq({'a' => 1})
    end
    
    it "should return trend data" do
      expect(Permissable.permissions_redis).to receive(:get).and_return(nil)
      expect(WeeklyStatsSummary).to receive(:trends).with(false).and_return({a: 1})
      get 'trends'
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq({'a' => 1})
    end
    
    it "should return additional data for admins" do
      o = Organization.create(:admin => true)
      token_user
      o.add_manager(@user.user_name, true)

      expect(Permissable.permissions_redis).to receive(:get).and_return(nil).at_least(1).times
      expect(WeeklyStatsSummary).to receive(:trends).with(true).and_return({a: 1})
      get 'trends'
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq({'a' => 1})
    end
  end
  
  describe "show" do
    it 'should require an api token' do
      get 'show', params: {id: 'asdf'}
      assert_missing_token
    end

    it 'should require a valid record' do
      token_user
      get 'show', params: {id: 'asdf'}
      assert_not_found('asdf')
    end

    it 'should require supervision authorization on the logged user' do
      token_user
      u = User.create
      d = Device.create(user: u)
      log = LogSession.process_new({
        :events => [
          {'timestamp' => 4.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
          {'timestamp' => 3.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => u, :device => d, :author => u})
      get :show, params: {:id => log.global_id}
      assert_unauthorized
    end

    it 'should return a log result' do
      token_user
      log = LogSession.process_new({
        :events => [
          {'timestamp' => 4.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
          {'timestamp' => 3.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => @user, :device => @device, :author => @user})
      get :show, params: {:id => log.global_id}
      json = JSON.parse(response.body)
      expect(json['log']['id']).to eq(log.global_id)
    end
  end
  
  describe "obl" do
    it 'should require an api token' do
      get 'obl'
      assert_missing_token
    end

    it 'should require a valid log id' do
      token_user
      get :obl, params: {log_id: 'asdf'}
      assert_not_found('asdf')
    end

    it 'should require supervision permission on the logged user' do
      token_user
      u = User.create
      d = Device.create(user: u)
      log = LogSession.process_new({
        :events => [
          {'timestamp' => 4.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
          {'timestamp' => 3.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => u, :device => d, :author => u})
      get :obl, params: {log_id: log.global_id}
      assert_unauthorized
    end

    it 'should return a progress record when generating for the log record' do
      token_user
      log = LogSession.process_new({
        :events => [
          {'timestamp' => 4.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
          {'timestamp' => 3.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => @user, :device => @device, :author => @user})
      get :obl, params: {:log_id => log.global_id}
      json = JSON.parse(response.body)
      expect(json['progress']).to_not eq(nil)
      p = Progress.last
      expect(p.settings['method']).to eq('export_log')
      expect(p.settings['arguments']).to eq([log.global_id])
    end

    it 'should require a valid user id if specified' do
      token_user
      get :obl, params: {user_id: 'asdf'}
      assert_not_found('asdf')
    end

    it 'should require supervision permission on the user if specified' do
      token_user
      u = User.create
      get :obl, params: {user_id: u.global_id}
      assert_unauthorized
    end

    it 'should return a progress record when generating for the user' do
      token_user
      get :obl, params: {user_id: @user.global_id}
      json = JSON.parse(response.body)
      expect(json['progress']).to_not eq(nil)
      p = Progress.last
      expect(p.settings['method']).to eq('export_logs')
      expect(p.settings['arguments']).to eq([@user.global_id, false])
    end
  end
end

# def obl
#   if params['log_id']
#     log = LogSession.find_by_global_id(params['log_id'])
#     return unless exists?(log, params['log_id'])
#     return unless exists?(log.user)
#     return unless allowed?(log.user, 'supervise')
#     progress = Progress.schedule(Exporter, :export_log, log.global_id)
#     render json: JsonApi::Progress.as_json(progress, :wrapper => true).to_json
#   elsif params['user_id']
#     user = User.find_by_global_id(params['user_id'])
#     return unless exists?(user, params['user_id'])
#     return unless allowed?(user, 'supervise')
#     progress = Progress.schedule(Exporter, :export_logs, user.global_id)
#     render json: JsonApi::Progress.as_json(progress, :wrapper => true).to_json
#   end
# end
