require 'spec_helper'

describe Api::OrganizationsController, :type => :controller do
  describe "index" do
    it "should require api token" do
      get :index
      assert_missing_token
    end
    
    it "should return unauthorized unless edit permissions allowed" do
      token_user
      get :index
      assert_unauthorized
    end
    
    it "should return unauthorized for a non-admin manager" do
      o = Organization.create
      token_user
      o.add_manager(@user.user_name, true)
      
      get :index
      assert_unauthorized
    end
    
    it "should return a list of organizations for an admin manager" do
      o = Organization.create(:admin => true)
      token_user
      o.add_manager(@user.user_name, true)
      
      get :index
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['organization'].length).to eq(1)
      expect(json['organization'][0]['id']).to eq(o.global_id)
    end
    
    
    it "should return a list of organizations for an admin assistant" do
      o = Organization.create(:admin => true)
      o2 = Organization.create
      token_user
      o.add_manager(@user.user_name, false)
      
      get :index
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['organization'].length).to eq(2)
      expect(json['organization'][0]['id']).to eq(o2.global_id)
      expect(json['organization'][1]['id']).to eq(o.global_id)
    end
    
    it "should return a paginated list of results" do
      o = Organization.create(:admin => true)
      30.times do
        Organization.create
      end
      token_user
      o.add_manager(@user.user_name, true)
      
      get :index
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['organization'].length).to eq(15)
      expect(json['meta']['offset']).to eq(0)
      expect(json['meta']['more']).to eq(true)
    end
  end
  
  describe "update" do
    it "should require api token" do
      put :update, :id => 1
      assert_missing_token
    end
    
    it "should return not found unless organization exists" do
      token_user
      put :update, :id => "1"
      assert_not_found("1")
    end
    
    it "should return unauthorized unless edit permissions allowed" do
      o = Organization.create
      token_user
      put :update, :id => o.global_id
      assert_unauthorized
    end
    
    it "should correctly update an organization" do
      token_user
      o = Organization.create
      o.add_manager(@user.user_name)
      put :update, :id => o.global_id, :organization => {:name => "my cool org"}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['organization']['id']).to eq(o.global_id)
      expect(json['organization']['name']).to eq('my cool org')
    end
    
    it "should not allow updating license count unless authorized" do
      token_user
      o = Organization.create
      o.add_manager(@user.user_name)
      put :update, :id => o.global_id, :organization => {:allotted_licenses => "7"}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['organization']['id']).to eq(o.global_id)
      expect(json['organization']['allotted_licenses']).to eq(0)
    end
    
    it "should not allow updating license expiration unless authorized" do
      token_user
      o = Organization.create
      o.add_manager(@user.user_name)
      put :update, :id => o.global_id, :organization => {:licenses_expire => '2020-01-01'}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['organization']['id']).to eq(o.global_id)
      expect(json['organization']['licenses_expire']).to eq(nil)
    end
    
    it "should allow updating license count if authorized" do
      token_user
      o = Organization.create(:admin => true)
      Organization.admin.add_manager(@user.user_name, true)
      put :update, :id => o.global_id, :organization => {:allotted_licenses => "7"}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['organization']['id']).to eq(o.global_id)
      expect(json['organization']['allotted_licenses']).to eq(7)
    end
    
    it "should allow updating license count if authorized" do
      token_user
      o = Organization.create(:admin => true)
      Organization.admin.add_manager(@user.user_name, true)
      put :update, :id => o.global_id, :organization => {:licenses_expire => "2020-01-01"}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['organization']['id']).to eq(o.global_id)
      expect(json['organization']['licenses_expire']).to eq(Time.parse("2020-01-01").iso8601)
    end
    
    describe "managing managers" do
      it "should allow adding a new manager" do
        token_user
        o = Organization.create
        o.add_manager(@user.user_name)
        u = User.create
        put :update, :id => o.global_id, :organization => {:management_action => "add_manager-#{u.user_name}"}
        expect(response.success?).to eq(true)
        expect(o.managed_user?(u.reload)).to eq(false)
        expect(o.manager?(u.reload)).to eq(true)
        expect(o.assistant?(u.reload)).to eq(true)
      end
      
      it "should allow adding a new assistant" do
        token_user
        o = Organization.create
        o.add_manager(@user.user_name)
        u = User.create
        put :update, :id => o.global_id, :organization => {:management_action => "add_assistant-#{u.user_name}"}
        expect(response.success?).to eq(true)
        expect(o.managed_user?(u.reload)).to eq(false)
        expect(o.assistant?(u.reload)).to eq(true)
        expect(o.manager?(u.reload)).to eq(false)
      end
      
      it "should fail gracefully when failing to add a manager" do
        token_user
        o = Organization.create
        o.add_manager(@user.user_name)
        put :update, :id => o.global_id, :organization => {:management_action => "add_manager-bob"}
        expect(response.success?).to eq(false)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('organization update failed')
        expect(json['errors']).to eq(['user management action failed: invalid user'])
      end

      it "should allow removing a manager" do
        token_user
        o = Organization.create
        o.add_manager(@user.user_name)
        u = User.create
        o.add_manager(u.user_name, true)
        put :update, :id => o.global_id, :organization => {:management_action => "remove_manager-#{u.user_name}"}
        expect(response.success?).to eq(true)
        expect(o.managed_user?(u.reload)).to eq(false)
        expect(o.assistant?(u.reload)).to eq(false)
        expect(o.manager?(u.reload)).to eq(false)
      end
      
      it "should allow removing an assistant" do
        token_user
        o = Organization.create
        o.add_manager(@user.user_name)
        u = User.create
        o.add_manager(u.user_name)
        put :update, :id => o.global_id, :organization => {:management_action => "remove_assistant-#{u.user_name}"}
        expect(response.success?).to eq(true)
        expect(o.managed_user?(u.reload)).to eq(false)
        expect(o.assistant?(u.reload)).to eq(false)
        expect(o.manager?(u.reload)).to eq(false)
      end
      
      it "should fail gracefully when removing an assistant" do
        token_user
        o = Organization.create
        o.add_manager(@user.user_name)
        put :update, :id => o.global_id, :organization => {:management_action => "remove_manager-bob"}
        expect(response.success?).to eq(false)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('organization update failed')
        expect(json['errors']).to eq(['user management action failed: invalid user'])
      end
    end
    
    describe "managing supervisors" do
      it "should allow adding a new supervisor" do
        token_user
        o = Organization.create
        o.add_manager(@user.user_name)
        u = User.create
        put :update, :id => o.global_id, :organization => {:management_action => "add_supervisor-#{u.user_name}"}
        expect(response.success?).to eq(true)
        expect(o.managed_user?(u.reload)).to eq(false)
        expect(o.supervisor?(u.reload)).to eq(true)
      end
      
      it "should fail gracefully when failing to add a supervisor" do
        token_user
        o = Organization.create
        o.add_manager(@user.user_name)
        put :update, :id => o.global_id, :organization => {:management_action => "add_supervisor-bob"}
        expect(response.success?).to eq(false)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('organization update failed')
        expect(json['errors']).to eq(['user management action failed: invalid user'])
      end

      it "should allow removing a supervisor" do
        token_user
        o = Organization.create
        o.add_manager(@user.user_name)
        u = User.create
        o.add_supervisor(u.user_name, true)
        put :update, :id => o.global_id, :organization => {:management_action => "remove_supervisor-#{u.user_name}"}
        o.reload
        expect(response.success?).to eq(true)
        expect(o.managed_user?(u.reload)).to eq(false)
        expect(o.manager?(u.reload)).to eq(false)
        expect(o.supervisor?(u.reload)).to eq(false)
      end
      
      it "should fail gracefully when removing a supervisor" do
        token_user
        o = Organization.create
        o.add_manager(@user.user_name)
        put :update, :id => o.global_id, :organization => {:management_action => "remove_supervisor-bob"}
        expect(response.success?).to eq(false)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('organization update failed')
        expect(json['errors']).to eq(['user management action failed: invalid user'])
      end
    end

    describe "managing users" do
      it "should allow adding a new user" do
        token_user
        o = Organization.create(:settings => {'total_licenses' => 1})
        o.add_manager(@user.user_name)
        u = User.create
        put :update, :id => o.global_id, :organization => {:management_action => "add_user-#{u.user_name}"}
        expect(response.success?).to eq(true)
        json = JSON.parse(response.body)
        expect(o.managed_user?(u.reload)).to eq(true)
        expect(o.sponsored_user?(u.reload)).to eq(true)
        expect(o.assistant?(u.reload)).to eq(false)
        expect(o.manager?(u.reload)).to eq(false)
      end
      
      it "should allow adding a new unsponsored user" do
        token_user
        o = Organization.create(:settings => {'total_licenses' => 1})
        o.add_manager(@user.user_name)
        u = User.create
        put :update, :id => o.global_id, :organization => {:management_action => "add_unsponsored_user-#{u.user_name}"}
        expect(response.success?).to eq(true)
        json = JSON.parse(response.body)
        expect(o.managed_user?(u.reload)).to eq(true)
        expect(o.sponsored_user?(u.reload)).to eq(false)
        expect(o.assistant?(u.reload)).to eq(false)
        expect(o.manager?(u.reload)).to eq(false)
      end
      
      it "should fail gracefully when failing to add a user" do
        token_user
        o = Organization.create(:settings => {'total_licenses' => 1})
        o.add_manager(@user.user_name)
        put :update, :id => o.global_id, :organization => {:management_action => "add_user-bob"}
        expect(response.success?).to eq(false)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('organization update failed')
        expect(json['errors']).to eq(['user management action failed: invalid user'])
      end
      
      it "should fail gracefully when no available license for new user" do
        token_user
        u = User.create
        o = Organization.create(:settings => {'total_licenses' => 0})
        o.add_manager(@user.user_name)
        put :update, :id => o.global_id, :organization => {:management_action => "add_user-#{u.user_name}"}
        expect(response.success?).to eq(false)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('organization update failed')
        expect(json['errors']).to eq(['user management action failed: no licenses available'])
      end
      
      it "should allow removing a user" do
        token_user
        o = Organization.create(:settings => {'total_licenses' => 1})
        o.add_manager(@user.user_name)
        u = User.create
        o.add_user(u.user_name, false)
        put :update, :id => o.global_id, :organization => {:management_action => "remove_user-#{u.user_name}"}
        expect(response.success?).to eq(true)
        json = JSON.parse(response.body)
        expect(o.managed_user?(u.reload)).to eq(false)
        expect(o.assistant?(u.reload)).to eq(false)
        expect(o.manager?(u.reload)).to eq(false)
      end
      
      it "should fail greacfully when railing to remove a user" do
        token_user
        o = Organization.create(:settings => {'total_licenses' => 1})
        o.add_manager(@user.user_name)
        put :update, :id => o.global_id, :organization => {:management_action => "remove_user-bob"}
        expect(response.success?).to eq(false)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('organization update failed')
        expect(json['errors']).to eq(['user management action failed: invalid user'])
      end
    end
  end
  
  describe "create" do
    it "should require api token" do
      post :create, :organization => {:name => "bob"}
      assert_missing_token
    end
    
    it "should require authorization" do
      token_user
      post :create, :organization => {:name => "bob"}
      assert_unauthorized
    end
    
    it "should properly create an org" do
      o = Organization.create(:admin => true)
      token_user
      o.add_manager(@user.user_name, true)
      post :create, :organization => {:name => "bob"}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['organization']).not_to eq(nil)
      expect(json['organization']['name']).to eq("bob")
    end
  end
  
  describe "destroy" do
    it "should require api token" do
      delete :destroy, :id => 1
      assert_missing_token
    end
    
    it "should return not found unless organization exists" do
      token_user
      delete :destroy, :id => "1"
      assert_not_found("1")
    end
    
    it "should return unauthorized without permissions allowed" do
      o = Organization.create
      token_user
      delete :destroy, :id => o.global_id
      assert_unauthorized
      
      o.add_manager(@user.user_name, true)
      delete :destroy, :id => o.global_id
      assert_unauthorized
    end
    
    it "should properly delete an org" do
      o = Organization.create(:admin => true)
      o2 = Organization.create
      token_user
      o.add_manager(@user.user_name, true)
      
      delete :destroy, :id => o2.global_id
      expect(response).to be_success
    end

    it "should not let anyone delete the admin org" do
      o = Organization.create(:admin => true)
      token_user
      o.add_manager(@user.user_name, true)
      
      delete :destroy, :id => o.global_id
      assert_unauthorized
    end
  end
  
  describe "show" do
    it "should require api token" do
      get :show, :id => 1
      assert_missing_token
    end
    
    it "should return not found unless organization exists" do
      token_user
      get :show, :id => "1"
      assert_not_found("1")
    end
    
    it "should return unauthorized unless edit permissions allowed" do
      o = Organization.create
      token_user
      get :show, :id => o.global_id
      assert_unauthorized
    end
    
    it "should return organization details" do
      o = Organization.create
      token_user
      o.add_manager(@user.user_name, false)
      get :show, :id => o.global_id
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['organization']['id']).to eq(o.global_id)
    end
  end
  
  describe "users" do
    it "should require api token" do
      get :users, :organization_id => 1
      assert_missing_token
    end
    
    it "should return not found unless organization exists" do
      token_user
      get :users, :organization_id => "1"
      assert_not_found("1")
    end
    
    it "should return unauthorized unless edit permissions allowed" do
      o = Organization.create
      token_user
      get :users, :organization_id => o.global_id
      assert_unauthorized
    end
    
    it "should return a paginated list of users if authorized" do
      o = Organization.create(:settings => {'total_licenses' => 100})
      token_user
      o.add_manager(@user.user_name)
      30.times do |i|
        u = User.create
        o.add_user(u.user_name, false)
      end
      
      get :users, :organization_id => o.global_id
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['meta']).not_to eq(nil)
      expect(json['user'].length).to eq(25)
      expect(json['meta']['next_url']).to eq("#{JsonApi::Json.current_host}/api/v1/organizations/#{o.global_id}/users?offset=#{JsonApi::User::DEFAULT_PAGE}&per_page=#{JsonApi::User::DEFAULT_PAGE}")
    end
  end
  
  describe "managers" do
    it "should require api token" do
      get :managers, :organization_id => 1
      assert_missing_token
    end
    
    it "should return not found unless organization exists" do
      token_user
      get :managers, :organization_id => "1"
      assert_not_found("1")
    end
    
    it "should return unauthorized unless edit permissions allowed" do
      o = Organization.create
      token_user
      get :managers, :organization_id => o.global_id
      assert_unauthorized
    end
    
    it "should return a paginated list of managers if authorized" do
      o = Organization.create
      token_user
      u = User.create
      o.add_manager(@user.user_name, true)
      o.add_manager(u.user_name, false)
      
      get :managers, :organization_id => o.global_id
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['meta']).not_to eq(nil)
      expect(json['user'].length).to eq(2)
      expect(json['user'][1]['id']).to eq(u.global_id)
      expect(json['user'][1]['org_manager']).to eq(false)
      expect(json['user'][1]['org_assistant']).to eq(true)
      expect(json['user'][0]['id']).to eq(@user.global_id)
      expect(json['user'][0]['org_manager']).to eq(true)
      expect(json['user'][0]['org_assistant']).to eq(true)
    end
  end

  describe "supervisors" do
    it "should require api token" do
      get :supervisors, :organization_id => 1
      assert_missing_token
    end
    
    it "should return not found unless organization exists" do
      token_user
      get :supervisors, :organization_id => "1"
      assert_not_found("1")
    end
    
    it "should return unauthorized unless edit permissions allowed" do
      o = Organization.create
      token_user
      get :supervisors, :organization_id => o.global_id
      assert_unauthorized
    end
    
    it "should return a paginated list of supervisors if authorized" do
      o = Organization.create
      token_user
      u = User.create
      u2 = User.create
      o.add_manager(@user.user_name, true)
      o.add_supervisor(u.user_name, false)
      o.add_supervisor(u2.user_name, true)
      
      get :supervisors, :organization_id => o.global_id
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['meta']).not_to eq(nil)
      expect(json['user'].length).to eq(2)
      expect(json['user'][0]['id']).to eq(u.global_id)
      expect(json['user'][0]['org_manager']).to eq(nil)
      expect(json['user'][0]['org_assistant']).to eq(nil)
      expect(json['user'][0]['org_supervision_pending']).to eq(false)      
      expect(json['user'][1]['id']).to eq(u2.global_id)
      expect(json['user'][1]['org_manager']).to eq(nil)
      expect(json['user'][1]['org_assistant']).to eq(nil)
      expect(json['user'][1]['org_supervision_pending']).to eq(true)      
    end
  end
  
  describe "logs" do
    it "should require api token" do
      get :logs, :organization_id => 1
      assert_missing_token
    end
    
    it "should return not found unless organization exists" do
      token_user
      get :logs, :organization_id => "1"
      assert_not_found("1")
    end
    
    it "should return unauthorized unless edit permissions allowed" do
      o = Organization.create
      token_user
      get :logs, :organization_id => o.global_id
      assert_unauthorized
    end
    
    it "should return unauthorized for assistants" do
      o = Organization.create(:settings => {'total_licenses' => 1})
      token_user
      u = User.create
      o.add_manager(@user.user_name)
      o.add_user(u.user_name, false)
      
      get :logs, :organization_id => o.global_id
      assert_unauthorized
    end
    
    it "should return a paginated list of logs if authorized" do
      o = Organization.create(:settings => {'total_licenses' => 100})
      token_user
      o.add_manager(@user.user_name, true)
      15.times do |i|
        u = User.create
        o.add_user(u.user_name, false)
        d = Device.create(:user => u)
        LogSession.process_new({
          :events => [
            {'timestamp' => 4.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'ok', 'board' => {'id' => '1_1'}}},
            {'timestamp' => 3.seconds.ago.to_i, 'type' => 'button', 'button' => {'label' => 'never mind', 'board' => {'id' => '1_1'}}}
          ]
        }, {:user => u, :device => d, :author => u})
      end
      
      get :logs, :organization_id => o.global_id
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['meta']).not_to eq(nil)
      expect(json['log'].length).to eq(10)
      expect(json['meta']['next_url']).to eq("#{JsonApi::Json.current_host}/api/v1/organizations/#{o.global_id}/logs?offset=#{JsonApi::Log::DEFAULT_PAGE}&per_page=#{JsonApi::Log::DEFAULT_PAGE}")
    end
  end
  
  describe "stats" do
    it "should require api token" do
      get :stats, :organization_id => '1_1234'
      assert_missing_token
    end
    
    it "should return not found unless org exists" do
      token_user
      get :stats, :organization_id => '1_1234'
      assert_not_found("1_1234")
    end
    
    it "should return unauthorized unless permissions allowed" do
      token_user
      o = Organization.create
      get :stats, :organization_id => o.global_id
      assert_unauthorized
    end
    
    it "should return expected stats" do
      token_user
      user = User.create
      d = Device.create(:user => user)
      o = Organization.create
      o.add_manager(@user.user_name, false)
      o.add_user(user.user_name, true, false)
      expect(o.reload.approved_users.length).to eq(0)
      get :stats, :organization_id => o.global_id
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq([])
      
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
      get :stats, :organization_id => o.global_id
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq([])
      
      o.add_user(user.user_name, false, false)
      expect(o.reload.approved_users.length).to eq(1)
      get :stats, :organization_id => o.global_id
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json.length).to eq(2)
      expect(json[0]['sessions']).to eq(1)
      expect(json[0]['timestamp']).to be > 0
      expect(json[1]['sessions']).to eq(1)
      expect(json[1]['timestamp']).to be > 0
    end
  end
  
  describe "admin_reports" do
    it "should require api token" do
      get :admin_reports, :organization_id => '1_1234'
      assert_missing_token
    end
    
    it "should return not found unless org exists" do
      token_user
      get :admin_reports, :organization_id => '1_1234'
      assert_not_found("1_1234")
    end
    
    it "should return unauthorized unless permissions allowed" do
      token_user
      o = Organization.create
      get :admin_reports, :organization_id => o.global_id
      assert_unauthorized
    end
    
    it "should require a report parameter" do
      token_user
      o = Organization.create(:admin => true)
      o.add_manager(@user.user_name, false)
      get :admin_reports, :organization_id => o.global_id
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['error']).to eq('report parameter required')
    end
    
    it "should error on an unrecognized report" do
      token_user
      o = Organization.create(:admin => true)
      o.add_manager(@user.user_name, false)
      get :admin_reports, :organization_id => o.global_id, :report => "good bacon"
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['error']).to eq('unrecognized report: good bacon')
    end
    
    it "should generate a report for premium_voices" do
      token_user
      o = Organization.create(:admin => true)
      o.add_manager(@user.user_name, false)
      ae1 = AuditEvent.create(:event_type => 'voice_added', :data => {'voice_id' => 'asd'})
      ae2 = AuditEvent.create(:data => {'voice_id' => 'asd'})
      ae3 = AuditEvent.create(:event_type => 'voice_added', :data => {'voice_id' => 'asd'})
      ae4 = AuditEvent.create(:event_type => 'voice_added', :data => {'voice_id' => 'asdf'})
      get :admin_reports, :organization_id => o.global_id, :report => "premium_voices"
      expect(response).to be_success
      json = JSON.parse(response.body)
      ts = Time.now.strftime('%m-%Y')
      expect(json['stats']).to eq({
        "#{ts} asd" => 2,
        "#{ts} asdf" => 1
      })
    end
    
    it "should not work on non-admin orgs" do
      token_user
      o = Organization.create
      o.add_manager(@user.user_name, false)
      
      get :admin_reports, :organization_id => o.global_id, :report => 'premium_voices'
      assert_unauthorized
    end
    
    it "should work on non-admin orgs for approved reports" do
      token_user
      o = Organization.create
      o.add_manager(@user.user_name, false)
      
      get :admin_reports, :organization_id => o.global_id, :report => 'logged_2'
      expect(response).to be_success
    end
    
    it "should generate other admin reports"
    
  end
end
