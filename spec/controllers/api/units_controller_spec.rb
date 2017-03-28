require 'spec_helper'

describe Api::UnitsController, :type => :controller do
  describe "index" do
    it "should require an api token" do
      get :index
      assert_missing_token
    end
    
    it "should require an existing org" do
      token_user
      get :index, params: {:organization_id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      o = Organization.create
      get :index, params: {:organization_id => o.global_id}
      assert_unauthorized
    end
    
    it "should return a paginated list" do
      token_user
      o = Organization.create
      o.add_manager(@user.global_id)
      ou = OrganizationUnit.create(:organization => o)
      ou2 = OrganizationUnit.create(:organization => o)
      get :index, params: {:organization_id => o.global_id}
      expect(response).to be_success
      res = JSON.parse(response.body)
      expect(res['unit']).to_not eq(nil)
      expect(res['unit'].length).to eq(2)
      expect(res['meta']['more']).to eq(false)
    end
  end

  describe "create" do
    it "should require an api token" do
      post :create
      assert_missing_token
    end
    
    it "should require an existing org" do
      token_user
      post :create, params: {:unit => {'organization_id' => 'asdf'}}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      o = Organization.create
      post :create, params: {:unit => {'organization_id' => o.global_id}}
      assert_unauthorized
    end
    
    it "should create the unit and return the result" do
      token_user
      o = Organization.create
      o.add_manager(@user.user_name)
      post :create, params: {:unit => {'organization_id' => o.global_id, 'name' => 'Cool Room'}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['unit']['name']).to eq('Cool Room')
    end
  end

  describe "show" do
    it "should require an api token" do
      get :show, params: {:id => 'asdf'}
      assert_missing_token
    end
    
    it "should require an existing record" do
      token_user
      get :show, params: {:id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      ou = OrganizationUnit.create
      get :show, params: {:id => ou.global_id}
      assert_unauthorized
    end
    
    it "should return the result" do
      token_user
      o = Organization.create
      o.add_manager(@user.user_name)
      ou = OrganizationUnit.create(:organization => o)
      get :show, params: {:id => ou.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['unit']['id']).to eq(ou.global_id)
    end
  end
  
  describe "update" do
    it "should require an api token" do
      put :update, params: {:id => 'asdf'}
      assert_missing_token
    end
    
    it "should require an existing record" do
      token_user
      put :update, params: {:id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      ou = OrganizationUnit.create
      put :update, params: {:id => ou.global_id}
      assert_unauthorized
    end
    
    it "should update the record and return the result" do
      token_user
      o = Organization.create
      o.add_manager(@user.user_name)
      ou = OrganizationUnit.create(:organization => o)
      put :update, params: {:id => ou.global_id, :unit => {'name' => 'Better Room'}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['unit']['id']).to eq(ou.global_id)
      expect(json['unit']['name']).to eq('Better Room')
    end
  end

  describe "destroy" do
    it "should require an api token" do
      delete :destroy, params: {:id => 'asdf'}
      assert_missing_token
    end
    
    it "should require an existing record" do
      token_user
      delete :destroy, params: {:id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      ou = OrganizationUnit.create
      delete :destroy, params: {:id => ou.global_id}
      assert_unauthorized
    end
    
    it "should delete the record and return the result" do
      token_user
      o = Organization.create
      o.add_manager(@user.user_name)
      ou = OrganizationUnit.create(:organization => o)
      delete :destroy, params: {:id => ou.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['unit']['id']).to eq(ou.global_id)
      expect(OrganizationUnit.find_by_global_id(ou.global_id)).to eq(nil)
    end
  end
  
  describe "stats" do
    it "should require api token" do
      get :stats, params: {:unit_id => '1_1234'}
      assert_missing_token
    end
    
    it "should return not found unless org exists" do
      token_user
      get :stats, params: {:unit_id => '1_1234'}
      assert_not_found("1_1234")
    end
    
    it "should return unauthorized unless permissions allowed" do
      token_user
      o = Organization.create
      u = OrganizationUnit.create(:organization => o)
      get :stats, params: {:unit_id => u.global_id}
      assert_unauthorized
    end
    
    it "should return expected stats" do
      token_user
      user = User.create
      d = Device.create(:user => user)
      o = Organization.create
      u = OrganizationUnit.create(:organization => o)
      o.add_user(user.user_name, false, false)
      o.add_supervisor(@user.user_name, false)
      u.add_supervisor(@user.user_name)
      expect(u.reload.all_user_ids.length).to eq(1)
      get :stats, params: {:unit_id => u.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq({'weeks' => [], 'user_weeks' => {}, 'user_counts' => {'goal_set' => 0, 'goal_recently_logged' => 0, 'recent_session_count' => 0, 'recent_session_user_count' => 0, 'total_users' => 0, 'recent_session_seconds' => 0.0, 'recent_session_hours' => 0.0}})
      
      LogSession.process_new({
        :events => [
          {'timestamp' => 4.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
          {'timestamp' => 3.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => user, :device => d, :author => user})
      LogSession.process_new({
        :events => [
          {'timestamp' => 4.weeks.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
          {'timestamp' => 4.weeks.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
        ]
      }, {:user => user, :device => d, :author => user})
      Worker.process_queues
      get :stats, params: {:unit_id => u.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq({'weeks' => [], 'user_weeks' => {}, 'user_counts' => {'goal_set' => 0, 'goal_recently_logged' => 0, 'recent_session_count' => 0, 'recent_session_user_count' => 0, 'total_users' => 0, 'recent_session_seconds' => 0.0, 'recent_session_hours' => 0.0}})
      
      expect(u.add_communicator(user.user_name)).to eq(true)
      expect(u.reload.all_user_ids.length).to eq(2)
      get :stats, params: {:unit_id => u.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)['weeks']
      expect(json.length).to eq(2)
      expect(json[0]['sessions']).to eq(1)
      expect(json[0]['timestamp']).to be > 0
      expect(json[1]['sessions']).to eq(1)
      expect(json[1]['timestamp']).to be > 0
    end
    
    it "should include goal stats" do
      token_user
      user = User.create
      user.settings['primary_goal'] = {
        'id' => 'asdf',
        'last_tracked' => Time.now.iso8601
      }
      user.save
      d = Device.create(:user => user)
      o = Organization.create
      u = OrganizationUnit.create(:organization => o)
      o.add_supervisor(@user.user_name, false)
      o.add_user(user.user_name, false, false)
      u.add_supervisor(@user.user_name)
      expect(u.reload.all_user_ids.length).to eq(1)
      get :stats, params: {:unit_id => u.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq({'weeks' => [], 'user_weeks' => {}, 'user_counts' => {'goal_set' => 0, 'goal_recently_logged' => 0, 'recent_session_count' => 0, 'recent_session_user_count' => 0, 'total_users' => 0, 'recent_session_seconds' => 0.0, 'recent_session_hours' => 0.0}})
      
      get :stats, params: {:unit_id => u.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['user_counts']).to eq({
        'goal_set' => 0,
        'goal_recently_logged' => 0, 
        'recent_session_count' => 0, 
        'recent_session_user_count' => 0, 
        'recent_session_seconds' => 0.0,
        'recent_session_hours' => 0.0,
        'total_users' => 0
      })
      
      u.add_communicator(user.user_name)
      expect(u.reload.all_user_ids.length).to eq(2)
      get :stats, params: {:unit_id => u.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['user_counts']).to eq({
        'goal_set' => 1,
        'goal_recently_logged' => 1,
        'recent_session_count' => 0, 
        'recent_session_user_count' => 0,
        'recent_session_seconds' => 0.0,
        'recent_session_hours' => 0.0, 
        'total_users' => 1
      })
    end
  end
  
  describe "logs" do
    it "should require api token" do
      get :logs, params: {:unit_id => '1_1234'}
      assert_missing_token
    end
    
    it "should return not found unless org exists" do
      token_user
      get :logs, params: {:unit_id => '1_1234'}
      assert_not_found("1_1234")
    end
    
    it "should return unauthorized unless permissions allowed" do
      token_user
      o = Organization.create
      u = OrganizationUnit.create(:organization => o)
      get :logs, params: {:unit_id => u.global_id}
      assert_unauthorized
    end
    
    it "should return a paginated list of logs if authorized" do
      o = Organization.create(:settings => {'total_licenses' => 100})
      unit = OrganizationUnit.create(:organization => o)
      token_user
      o.add_manager(@user.user_name, true)
      15.times do |i|
        u = User.create
        o.add_user(u.user_name, false)
        unit.add_communicator(u.user_name)
        d = Device.create(:user => u)
        LogSession.process_new({
          :events => [
            {'timestamp' => 4.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
            {'timestamp' => 3.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
          ]
        }, {:user => u, :device => d, :author => u})
      end
      
      get :logs, params: {:unit_id => unit.global_id}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['meta']).not_to eq(nil)
      expect(json['log'].length).to eq(10)
      expect(json['meta']['next_url']).to eq("#{JsonApi::Json.current_host}/api/v1/units/#{unit.global_id}/logs?offset=#{JsonApi::Log::DEFAULT_PAGE}&per_page=#{JsonApi::Log::DEFAULT_PAGE}")
    end
  end
end
