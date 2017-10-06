require 'spec_helper'

describe Api::UsersController, :type => :controller do
  describe "show" do
    it "should not require api token" do
      u = User.create
      get :show, params: {:id => u.global_id}
      expect(response).to be_success
    end
    
    it "should require a valid record" do
      get :show, params: {:id => "asdf"}
      assert_not_found('asdf');
    end

    it "should return a valid object" do
      u = User.create
      get :show, params: {:id => u.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['user']['id']).to eq(u.global_id)
      expect(json['user']['subscription']).to eq(nil)
      expect(json['user']['user_token']).to eq(nil)
    end
    
    it "should allow access with a confirmation code" do
      u = User.create
      get :show, params: {:id => u.global_id, :confirmation => u.registration_code}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['user']['id']).to eq(u.global_id)
      expect(json['user']['subscription']).to_not eq(nil)
      expect(json['user']['user_token']).to eq(nil)
    end
    
    it "should return restricted information with only a confirmation code" do
      u = User.create
      get :show, params: {:id => u.global_id, :confirmation => u.registration_code}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['user']['id']).to eq(u.global_id)
      expect(json['user']['subscription']).to_not eq(nil)
      expect(json['user']['user_token']).to eq(nil)
    end
    
    it "should return full information if authorized, while also having a confirmation code" do
      token_user
      get :show, params: {:id => @user.global_id, :confirmation => @user.registration_code}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['user']['id']).to eq(@user.global_id)
      expect(json['user']['subscription']).to_not eq(nil)
      expect(json['user']['permissions']['edit']).to eq(true)
      expect(json['user']['user_token']).to_not eq(nil)
    end
    
    it "should return self information with a limited api scope" do
      token_user
      @device.developer_key_id = 1
      @device.settings['permission_scopes'] = ['read_profile']
      @device.save
      expect(@device.permission_scopes).to eq(['read_profile'])
      get :show, params: {:id => 'self'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['user']['id']).to eq(@user.global_id)
      expect(json['user']['preferences']).to eq(nil)
      expect(json['user']['permissions']['edit']).to eq(false)
    end
    
    it "should not return supervisee information with a limited api scope" do
      token_user
      @device.developer_key_id = 1
      @device.settings['permission_scopes'] = ['read_profile']
      @device.save
      u = User.create
      u.permission_scopes_device = @device
      
      User.link_supervisor_to_user(@user, u)
      expect(u.permission_scopes).to eq(['read_profile'])
      expect(u.permissions_for(u, u.permission_scopes)).to eq({
        "user_id"=>u.global_id, 
        "view_existence"=>true, 
        "view_detailed"=>true,
        "view_deleted_boards"=>true, 
        "supervise"=>false, 
        "edit"=>false, 
        "manage_supervision"=>false, 
        "delete"=>false
      })

      get :show, params: {:id => 'self'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['user']['id']).to eq(@user.global_id)
      expect(json['user']['supervisees']).to eq(nil)
    end
    
    it "should not allow looking up supervisees with a limited api scope" do
      token_user
      @device.developer_key_id = 1
      @device.settings['permission_scopes'] = ['read_profile']
      @device.save
      u = User.create
      User.link_supervisor_to_user(@user, u)
      get :show, params: {:id => u.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['user']['id']).to eq(u.global_id)
      expect(json['user']['supervisees']).to eq(nil)
      expect(json['user']['preferences']).to eq(nil)
    end

    it "should allow looking up supervisees with a full api scope" do
      token_user
      @device.developer_key_id = 1
      @device.settings['permission_scopes'] = ['full']
      @device.save
      u = User.create
      u.permission_scopes_device = @device
      expect(u.permission_scopes).to eq(['full'])

      User.link_supervisor_to_user(@user, u)
      expect(u.permissions_for(@user)).to eq({
        'user_id' => @user.global_id,
        "view_existence"=>true, 
        "edit"=>true, 
        "manage_supervision"=>true, 
        "view_deleted_boards"=>true, 
        "view_detailed"=>true, 
        "supervise"=>true
      })
      
      get :show, params: {:id => u.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['user']['permissions']).to eq({
        'user_id' => @user.global_id,
        "view_existence"=>true, 
        "edit"=>true, 
        "manage_supervision"=>true, 
        "view_deleted_boards"=>true, 
        "view_detailed"=>true, 
        "supervise"=>true
      })
      expect(json['user']['id']).to eq(u.global_id)
      expect(json['user']['preferences']).to_not eq(nil)
    end
  end
  
  describe "index" do
    it "should require api token" do
      get :index
      assert_missing_token
    end
    
    it "should require admin manager position" do
      token_user
      get :index
      assert_error 'admins only'
    end
    
    it "should require a query parameter" do
      token_user
      o = Organization.create(:admin => true, :settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, true)
      get :index
      assert_error ('q parameter required')
    end
    
    it "should return results" do
      u = User.create(:user_name => 'bob')
      u2 = User.create(:user_name => 'bobby')

      token_user
      o = Organization.create(:admin => true, :settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, true)
      get :index, params: {:q => 'bo'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).not_to eq(nil)
      expect(json['user'].length).to eq(2)
      expect(json['user'][0]['id']).to eq(u.global_id)
      expect(json['user'][1]['id']).to eq(u2.global_id)
    end
    
    it "should return email results for an email query" do
      u = User.create(:user_name => 'bob@example.com')
      u2 = User.create(:user_name => 'boby', :settings => {'email' => 'bob@example.com'})
      u3 = User.create(:user_name => 'bobby', :settings => {'email' => 'bob@example.com'})

      token_user
      o = Organization.create(:admin => true, :settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, true)
      get :index, params: {:q => 'bob@example.com'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).not_to eq(nil)
      expect(json['user'].length).to eq(2)
      expect(json['user'][0]['id']).to eq(u3.global_id)
      expect(json['user'][1]['id']).to eq(u2.global_id)

      get :index, params: {:q => 'bob@'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).not_to eq(nil)
      expect(json['user'].length).to eq(0)
    end
    
    it "should return a single result if perfect match on user_name" do
      u = User.create(:user_name => 'bob')
      u2 = User.create(:user_name => 'bobby')

      token_user
      o = Organization.create(:admin => true, :settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, true)
      get :index, params: {:q => 'bob'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).not_to eq(nil)
      expect(json['user'].length).to eq(1)
      expect(json['user'][0]['id']).to eq(u.global_id)
    end
    
    it "should paginate results" do
      us = []
      30.times do |i|
        us << User.create(:user_name => "betsy#{i}")
      end
      
      token_user
      o = Organization.create(:admin => true, :settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, true)
      get :index, params: {:q => 'betsy'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).not_to eq(nil)
      expect(json['user'].length).to eq(25)
      expect(json['user'][0]['id']).to eq(us[0].global_id)
      expect(json['user'][1]['id']).to eq(us[1].global_id)
      expect(json['user'][2]['id']).to eq(us[10].global_id)
      expect(json['user'][3]['id']).to eq(us[11].global_id)
      expect(json['user'][4]['id']).to eq(us[12].global_id)
    end
  end
  
  describe "update" do
    it "should not require api token" do
      post :update, params: {:id => 123}
      expect(response).not_to be_success
      expect(response.body).not_to match(/Access token required/)
    end
    
    it "should error if neither reset token nor authorized api token" do
      u = User.create
      token_user
      post :update, params: {:id => u.global_id, :user => {'name' => 'bob'}}
      assert_unauthorized
    end
    
    it "should only allow for resetting passwords if there's an active reset token" do
      u = User.create
      u.generate_password_reset
      code = u.password_reset_code
      token = u.reset_token_for_code(code)
      expect(u.reload.valid_reset_token?(token)).to eq(true)
      post :update, params: {:id => u.global_id, :reset_token => token, :user => {'password' => '12345678'}}
      expect(response).to be_success
      expect(u.reload.valid_password?('12345678')).to eq(true)

      post :update, params: {:id => u.global_id, :reset_token => "abcdefg", :user => {'password' => '98765432'}}
      assert_unauthorized

      post :update, params: {:id => u.global_id, :reset_token => token, :user => {'password' => '98765432'}}
      assert_unauthorized
    end
    
    it "should let admins reset passwords for users" do
      token_user
      u = User.create
      o = Organization.create(:settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, true)
      o.add_user(u.user_name, false)
      
      post :update, params: {:id => u.global_id, :reset_token => 'admin', :user => {'name' => 'fred', 'password' => '2345654'}}
      expect(response).to be_success
      expect(u.reload.valid_password?('2345654')).to eq(true)
      expect(u.settings['name']).to eq('No name')
    end
    
    it "should not let non-admins reset passwords for users" do
      token_user
      u = User.create
      o = Organization.create(:settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, false)
      o.add_user(u.user_name, false)
      
      post :update, params: {:id => u.global_id, :reset_token => 'admin', :user => {'name' => 'fred', 'password' => '2345654'}}
      assert_unauthorized
    end
    
    it "should not let admins that aren't over a user reset that user's password" do
      token_user
      u = User.create
      o = Organization.create(:settings => {'total_licenses' => 1})
      o2 = Organization.create(:settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, true)
      o2.add_user(u.user_name, false)
      
      post :update, params: {:id => u.global_id, :reset_token => 'admin', :user => {'name' => 'fred', 'password' => '2345654'}}
      assert_unauthorized
    end
    
    it "should update parameters if allowed" do
      token_user
      post :update, params: {:id => @user.global_id, :user => {:name => 'bob'}}
      expect(response).to be_success
      expect(@user.reload.settings['name']).to eq('bob')
    end
    
    it "should update device-specific settings if for the current user" do
      token_user
      post :update, params: {:id => @user.global_id, :user => {:name => 'bob', :preferences => {:device => {:a => 1}}}}
      expect(response).to be_success
      @user.reload
      expect(@user.settings['name']).to eq('bob')
      expect(@user.settings['preferences']['devices']).not_to eq(nil)
      expect(@user.settings['preferences']['devices'][@device.unique_device_key]['a']).to eq('1')
    end
    
    it "should not update device-specific settings if not for the current user" do
      token_user
      @user2 = User.create(:settings => {'supervisors' => [{'user_id' => @user.global_id, 'edit_permission' => true}]})
      expect(@user.supervisor_for?(@user2)).to eq(true)
      post :update, params: {:id => @user2.global_id, :user => {:name => 'bob', :preferences => {:device => {:a => 1}}}}
      expect(response).to be_success
      @user2.reload
      expect(@user2.settings['name']).to eq('bob')
      expect(@user2.settings['preferences']['devices']).not_to eq(nil)
      expect(@user2.settings['preferences']['devices'][@device.unique_device_key]).to eq(nil)
      expect(@user2.settings['preferences']['devices']['default']['a']).to eq('1')
    end
    
    it "should fail gracefully on user update fail" do
      token_user
      expect_any_instance_of(User).to receive(:process_params){|u| u.add_processing_error("bacon") }.and_return(false)
      post :update, params: {:id => @user.global_id, :user => {:name => 'bob', :preferences => {:device => {:a => 1}}}}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['error']).to eq("update failed")
      expect(json['errors']).to eq(["bacon"])
    end
    
    it "should allow an edit supervisor to change the home board for the current user" do
      token_user
      u2 = User.create
      b = Board.create(:user => u2)
      User.link_supervisor_to_user(@user, u2, nil, true)
      put :update, params: {:id => u2.global_id, :user => {:preferences => {:home_board => {:id => b.global_id, :key => b.key}}}}
      expect(response).to be_success
      expect(u2.reload.settings['preferences']['home_board']['id']).to eq(b.global_id)
    end
    
    it "should allow an edit supervisor to set the home board to one of the supervisor's private boards" do
      token_user
      u2 = User.create
      b = Board.create(:user => @user)
      User.link_supervisor_to_user(@user, u2, nil, true)
      put :update, params: {:id => u2.global_id, :user => {:preferences => {:home_board => {:id => b.global_id, :key => b.key}}}}
      expect(response).to be_success
      expect(u2.reload.settings['preferences']['home_board']['id']).to eq(b.global_id)
      expect(b.reload.shared_with?(u2)).to eq(true)
    end
    
    it "should now allow an edit supervisor to set the home board to one they don't have sharing permissions for" do
      token_user
      u2 = User.create
      u3 = User.create
      b = Board.create(:user => u3)
      expect(b.allows?(@user, 'view')).to eq(false)
      expect(b.allows?(u2, 'view')).to eq(false)
      expect(b.allows?(u3, 'view')).to eq(true)
      
      User.link_supervisor_to_user(@user, u2, nil, true)
      put :update, params: {:id => u2.global_id, :user => {:preferences => {:home_board => {:id => b.global_id, :key => b.key}}}}
      expect(response).to be_success
      expect(u2.reload.settings['preferences']['home_board']).to eq(nil)
      expect(b.reload.shared_with?(u2)).to eq(false)
    end
  end
  
  describe "create" do
    it "should not require api token" do
      post :create, params: {:user => {'name' => 'fred'}}
      expect(response).to be_success
    end
    
    it "should schedule delivery of a welcome message" do
      expect(UserMailer).to receive(:schedule_delivery).exactly(2).times
      post :create, params: {:user => {'name' => 'fred'}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['user']['name']).to eq('fred')
    end
    
    it "should include access token information" do
      post :create, params: {:user => {'name' => 'fred'}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['meta']['access_token']).not_to be_nil
    end
    
    it "should have correct defaults" do
      post :create, params: {:user => {'name' => 'fred'}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      user = json['user']
      expect(user).not_to eq(nil)
      expect(user['preferences']).not_to eq(nil)
      expect(user['preferences']['auto_home_return']).to eq(true)
      expect(user['preferences']['clear_on_vocalize']).to eq(true)
      expect(user['preferences']['logging']).to eq(false)
    end
    
    it "should error gracefully on user create fail" do
      expect_any_instance_of(User).to receive(:process_params){|u| u.add_processing_error("bacon") }.and_return(false)
      post :create, params: {:user => {'name' => 'fred'}}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['error']).to eq("user creation failed")
      expect(json['errors']).to eq(["bacon"])
    end
    
    it "should track the new user externally" do
      expect(ExternalTracker).to receive(:track_new_user)
      post :create, params: {:user => {'name' => 'fred'}}
      expect(response).to be_success
    end
    
    it "should throttle or captcha or something to prevent abuse"
  end
  
  describe "replace_board" do
    it "should require api token" do
      post :replace_board, params: {:user_id => 1, :old_board_id => 1, :new_board_id => 2}
      assert_missing_token
    end
    
    it "should return a progress object" do
      token_user
      b1 = Board.create(:user => @user)
      b2 = Board.create(:user => @user)
      post :replace_board, params: {:user_id => @user.global_id, :old_board_id => b1.global_id, :new_board_id => b2.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['progress']['id']).not_to eq(nil)
    end
    
    it "should require permissions for the user, old and new boards" do
      u = User.create
      token_user
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u)
      post :replace_board, params: {:user_id => u.global_id, :old_board_id => b1.global_id, :new_board_id => b2.global_id, :access_token => @device.token, :check_token => true}
      assert_unauthorized
      
      b1.user = @user
      b1.save
      post :replace_board, params: {:user_id => u.global_id, :old_board_id => b1.global_id, :new_board_id => b2.global_id, :access_token => @device.token, :check_token => true}
      assert_unauthorized

      b2.user = @user
      b2.save
      post :replace_board, params: {:user_id => u.global_id, :old_board_id => b1.global_id, :new_board_id => b2.global_id, :access_token => @device.token, :check_token => true}
      assert_unauthorized
      
      post :replace_board, params: {:user_id => @user.global_id, :old_board_id => b1.global_id, :new_board_id => b2.global_id, :access_token => @device.token, :check_token => true}
      expect(response).to be_success
      
      User.link_supervisor_to_user(@user, u, nil, true)
      post :replace_board, params: {:user_id => u.global_id, :old_board_id => b1.global_id, :new_board_id => b2.global_id, :access_token => @device.token, :check_token => true}
      expect(response).to be_success
    end
  end
  
  describe "copy_board_links" do
    it "should require api token" do
      post :copy_board_links, params: {:user_id => 1, :old_board_id => 1, :new_board_id => 2}
      assert_missing_token
    end
    
    it "should return a progress object" do
      token_user
      b1 = Board.create(:user => @user)
      b2 = Board.create(:user => @user)
      post :copy_board_links, params: {:user_id => @user.global_id, :old_board_id => b1.global_id, :new_board_id => b2.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['progress']['id']).not_to eq(nil)
    end
    
    it "should require permissions for the user, old and new boards" do
      u = User.create
      token_user
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u)
      post :copy_board_links, params: {:user_id => u.global_id, :old_board_id => b1.global_id, :new_board_id => b2.global_id, :access_token => @device.token, :check_token => true}
      assert_unauthorized
      
      b1.user = @user
      b1.save
      post :copy_board_links, params: {:user_id => u.global_id, :old_board_id => b1.global_id, :new_board_id => b2.global_id, :access_token => @device.token, :check_token => true}
      assert_unauthorized

      b2.user = @user
      b2.save
      post :copy_board_links, params: {:user_id => u.global_id, :old_board_id => b1.global_id, :new_board_id => b2.global_id, :access_token => @device.token, :check_token => true}
      assert_unauthorized
      
      post :copy_board_links, params: {:user_id => @user.global_id, :old_board_id => b1.global_id, :new_board_id => b2.global_id, :access_token => @device.token, :check_token => true}
      expect(response).to be_success
      
      User.link_supervisor_to_user(@user, u, nil, true)
      post :copy_board_links, params: {:user_id => u.global_id, :old_board_id => b1.global_id, :new_board_id => b2.global_id, :access_token => @device.token, :check_token => true}
      expect(response).to be_success
    end
  end
  
  describe "hide_device" do
    it "should require api token" do
      delete :hide_device, params: {:user_id => 1, :device_id => 1}
      assert_missing_token
    end
    
    it "should require permission for the user" do
      token_user
      u = User.create
      delete :hide_device, params: {:user_id => u.user_name, :device_id => 1}
      assert_unauthorized
    end
    
    it "should only allow hiding devices for the specified user" do
      token_user
      u2 = User.create
      d = Device.create(:user => u2)
      delete :hide_device, params: {:user_id => @user.user_name, :device_id => d.global_id}
      expect(response.success?).to eq(false)
      expect(JSON.parse(response.body)['error']).to eq('matching device not found')
    end
    
    it "should successfully hide the device" do
      token_user
      d = Device.create(:user => @user)
      delete :hide_device, params: {:user_id => @user.user_name, :device_id => d.global_id}
      expect(response.success?).to eq(true)
      expect(JSON.parse(response.body)['hidden']).to eq(true)
    end
  end
  
  describe "rename_device" do
    it "should require api token" do
      put :rename_device, params: {:user_id => 1, :device_id => 1, :device => {:name => 'fred'}}
      assert_missing_token
    end
    
    it "should require permission for the user" do
      token_user
      u = User.create
      put :rename_device, params: {:user_id => u.user_name, :device_id => 1, :device => {:name => 'fred'}}
      assert_unauthorized
    end
    
    it "should only allow hiding devices for the specified user" do
      token_user
      u2 = User.create
      d = Device.create(:user => u2)
      put :rename_device, params: {:user_id => @user.user_name, :device_id => d.global_id, :device => {:name => 'fred'}}
      expect(response.success?).to eq(false)
      expect(JSON.parse(response.body)['error']).to eq('matching device not found')
    end
    
    it "should successfully hide the device" do
      token_user
      d = Device.create(:user => @user)
      put :rename_device, params: {:user_id => @user.user_name, :device_id => d.global_id, :device => {:name => 'fred'}}
      expect(response.success?).to eq(true)
      expect(JSON.parse(response.body)['name']).to eq('fred')
    end
  end
  
  describe "confirm_registration" do
    it "should not require api token" do
      post :confirm_registration, params: {:user_id => 1, :code => 'asdf'}
      expect(response).to be_success
    end
    
    it "should not error on invalid parameters" do
      post :confirm_registration, params: {:user_id => 1, :code => 'asdf'}
      expect(response).to be_success
      expect(response.body).to eq({confirmed: false}.to_json)
    end
    
    it "should return whether registration was confirmed or not" do
      u = User.create
      post :confirm_registration, params: {:user_id => u.global_id, :code => u.registration_code}
      expect(response).to be_success
      expect(response.body).to eq({confirmed: true}.to_json)

      post :confirm_registration, params: {:user_id => u.global_id, :code => u.registration_code}
      expect(response).to be_success
      expect(response.body).to eq({confirmed: true}.to_json)

      post :confirm_registration, params: {:user_id => u.global_id, :code => "abc"}
      expect(response).to be_success
      expect(response.body).to eq({confirmed: false}.to_json)
    end
  end

  describe "forgot_password" do
    it "should not require api token" do
      u = User.create(:settings => {'email' => 'bob@example.com'})
      post :forgot_password, params: {:key => u.user_name}
      expect(response).to be_success
    end
    
    it "should throttle token creation and emailing" do
      u = User.create
      10.times{|i| u.generate_password_reset }
      u.save
      expect(UserMailer).not_to receive(:schedule_delivery)
      post :forgot_password, params: {:key => u.user_name}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['email_sent']).to eq(false)
      expect(json['users']).to eq(0)
      expect(json['message']).to eq('The user matching that name or email has had too many password resets. Please wait at least three hours and try again.')
    end
    
    it "should return message when no users found" do
      post :forgot_password, params: {:key => 'shoelace'}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['email_sent']).to eq(false)
      expect(json['users']).to eq(0)
      expect(json['message']).to eq('No users found with that name or email.')
    end
    
    
    it "should schedule a message delivery when non-throttled user is found" do
      u = User.create(:settings => {'email' => 'bob@example.com'})
      expect(UserMailer).to receive(:schedule_delivery)
      post :forgot_password, params: {:key => u.user_name}
      expect(response).to be_success
    end
    
    it "should return a success message when no users found but an email address provided" do
      post :forgot_password, params: {:key => 'shoelace@example.com'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['email_sent']).to eq(true)
    end
    
    it "should schedule a message delivery when no user found by an email address provided" do
      expect(UserMailer).to receive(:schedule_delivery).with(:login_no_user, 'shoelace@example.com')
      post :forgot_password, params: {:key => 'shoelace@example.com'}
      expect(response).to be_success
    end

    it "should not include disabled emails" do
      u = User.create(:settings => {'email' => 'bob@example.com', 'email_disabled' => true})
      expect(UserMailer).not_to receive(:schedule_delivery)
      post :forgot_password, params: {:key => u.user_name}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['email_sent']).to eq(false)
      expect(json['users']).to eq(0)
      expect(json['message']).to eq('The email address for that account has been manually disabled.')
    end
    
    it "should include possibly-multiple users for the given email address" do
      u = User.create(:settings => {'email' => 'bob@example.com'})
      post :forgot_password, params: {:key => u.user_name}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['email_sent']).to eq(true)
      expect(json['users']).to eq(1)
      
      u2 = User.create(:settings => {'email' => 'bob@example.com'})
      post :forgot_password, params: {:key => 'bob@example.com'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['email_sent']).to eq(true)
      expect(json['users']).to eq(2)
    end
    it "should provide helpful message if some user accounts but not others were throttled" do
      u = User.create(:settings => {'email' => 'bob@example.com'})
      u2 = User.create(:settings => {'email' => 'bob@example.com'})
      10.times{|i| u.generate_password_reset }
      u.save
      expect(UserMailer).to receive(:schedule_delivery)
      post :forgot_password, params: {:key => 'bob@example.com'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['email_sent']).to eq(true)
      expect(json['users']).to eq(2)
      expect(json['message']).to eq("One or more of the users matching that name or email have had too many password resets, so those links weren't emailed to you. Please wait at least three hours and try again.")
    end
  end  

  describe "password_reset" do
    it "should not require api token" do
      post :password_reset, params: {:user_id => 1, :code => 'abc'}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['valid']).to eq(false)
    end
    
    it "should throttle to prevent brute force attacks"
    
    it "should return whether the code is valid" do
      post :password_reset, params: {:user_id => 1, :code => 'abc'}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['valid']).to eq(false)
    end
    
    it "should return a reset token on valid code exchange" do
      u = User.create
      u.generate_password_reset
      post :password_reset, params: {:user_id => u.global_id, :code => u.password_reset_code}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['valid']).to eq(true)
      expect(json['reset_token']).not_to eq(nil)
      expect(u.reload.valid_reset_token?(json['reset_token'])).to eq(true)
    end
  end
  
  describe "flush_logs" do
    it "should require api token" do
      post :flush_logs, params: {:user_id => 1}
      assert_missing_token
    end
    
    it "should require delete permission" do
      token_user
      @user2 = User.create(:settings => {'supervisors' => [{'user_id' => @user.global_id, 'edit_permission' => true}]})
      expect(@user.supervisor_for?(@user2)).to eq(true)
      post :flush_logs, params: {:user_id => @user2.global_id}
      assert_unauthorized
    end
    
    it "should error if user_name is not provided correctly" do
      token_user
      post :flush_logs, params: {:user_id => @user.global_id}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['flushed']).to eq("false")
    end
    
    it "should return a progress object" do
      token_user
      post :flush_logs, params: {:user_id => @user.global_id, :user_name => @user.user_name}
      expect(response).to be_success
      json = JSON.parse(response.body)
      progress = Progress.find_by_global_id(json['progress']['id'])
      expect(progress.settings['class']).to eq('Flusher')
      expect(progress.settings['method']).to eq('flush_user_logs')
      expect(progress.settings['arguments']).to eq([@user.global_id, @user.user_name])
    end
  end
  
  describe "flush_user" do
    it "should require api token" do
      post :flush_user, params: {:user_id => 1}
      assert_missing_token
    end
    
    it "should require delete permission" do
      token_user
      @user2 = User.create(:settings => {'supervisors' => [{'user_id' => @user.global_id, 'edit_permission' => true}]})
      expect(@user.supervisor_for?(@user2)).to eq(true)
      post :flush_user, params: {:user_id => @user2.global_id}
      assert_unauthorized
    end
    
    it "should error if user_name is not provided correctly" do
      token_user
      post :flush_user, params: {:user_id => @user.global_id}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['flushed']).to eq("false")
    end
    
    it "should return a progress object" do
      token_user
      post :flush_user, params: {:user_id => @user.global_id, :user_name => @user.user_name}
      expect(response).to be_success
      json = JSON.parse(response.body)
      progress = Progress.find_by_global_id(json['progress']['id'])
      expect(progress.settings['class']).to eq('Flusher')
      expect(progress.settings['method']).to eq('flush_user_completely')
      expect(progress.settings['arguments']).to eq([@user.global_id, @user.user_name])
    end
  end

  describe "daily_stats" do
    it "should require an api token" do
      get 'daily_stats', params: {:user_id => 'asdf'}
      assert_missing_token
    end
    
    it "should error on expected errors" do
      token_user
      expect(Stats).to receive(:daily_use).with(@user.global_id, {}).and_raise(Stats::StatsError, 'bacon')
      get 'daily_stats', params: {:user_id => @user.global_id}
      expect(response.code).to eq("400")
      json = JSON.parse(response.body)
      expect(json['error']).to eq('bacon')
    end
    
    it "should return a stats result" do
      token_user
      get 'daily_stats', params: {:user_id => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['start_at']).not_to eq(nil)
      expect(json['end_at']).not_to eq(nil)
      expect(json['total_utterances']).to eq(0)
    end
    
    it "should use the provided date range" do
      token_user
      get 'daily_stats', params: {:user_id => @user.global_id, :start => '2014-01-01', :end => '2014-03-01'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['start_at']).to match('2014-01-01')
      expect(json['end_at']).to match('2014-03-01')
      expect(json['total_utterances']).to eq(0)
    end
    
    it "should error on too large a date range" do
      token_user
      get 'daily_stats', params: {:user_id => @user.global_id, :start => '2014-01-01', :end => '2014-10-01'}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['error']).to eq('time window cannot be greater than 6 months')
    end
  end  

  describe "hourly_stats" do
    it "should require an api token" do
      get 'hourly_stats', params: {:user_id => 'asdf'}
      assert_missing_token
    end
    
    it "should error on expected errors" do
      token_user
      expect(Stats).to receive(:hourly_use).with(@user.global_id, {}).and_raise(Stats::StatsError, 'bacon')
      get 'hourly_stats', params: {:user_id => @user.global_id}
      expect(response.code).to eq("400")
      json = JSON.parse(response.body)
      expect(json['error']).to eq('bacon')
    end
    
    it "should return a stats result" do
      token_user
      get 'hourly_stats', params: {:user_id => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['start_at']).not_to eq(nil)
      expect(json['end_at']).not_to eq(nil)
      expect(json['total_utterances']).to eq(0)
    end
  end
  
  describe "subscribe" do
    it "should require an api token" do
      post :subscribe, params: {:user_id => 'asdf'}
      assert_not_found('asdf')
    end

    it "should require edit permissions" do
      token_user
      u = User.create
      post :subscribe, params: {:user_id => u.global_id}
      assert_unauthorized
    end

    it "should schedule token processing" do
      token_user
      p = Progress.create
      expect(Progress).to receive(:schedule).with(@user, :process_subscription_token, {'code' => 'abc'}, 'monthly_6').and_return(p)
      post :subscribe, params: {:user_id => @user.global_id, :token => {'code' => 'abc'}, :type => 'monthly_6'}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['progress']).not_to eq(nil)
    end
    
    it "should allow redeeming a gift purchase" do
      token_user
      p = Progress.create
      expect(Progress).to receive(:schedule).with(@user, :redeem_gift_token, 'abc').and_return(p)
      post :subscribe, params: {:user_id => @user.global_id, :token => {'code' => 'abc'}, :type => 'gift_code'}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['progress']).not_to eq(nil)
    end

    it "should process the redemption" do
      g = GiftPurchase.process_new({}, {
        'email' => 'bob@example.com',
        'seconds' => 3.years.to_i
      })
      token_user
      exp = @user.expires_at
      
      post :subscribe, params: {:user_id => @user.global_id, :token => {'code' => g.code}, :type => 'gift_code'}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['progress']).not_to eq(nil)
      id = json['progress']['id']
      
      Worker.process_queues
      progress = Progress.find_by_global_id(id)
      expect(progress.settings['state']).to eq('finished')

      @user.reload
      expect(@user.expires_at).to eq(exp + 3.years.to_i)
    end
    
    it "should let admins set a subscription to never_expires" do
      token_user
      u = User.create
      o = Organization.create(:admin => true, :settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, true)
      
      post :subscribe, params: {:user_id => u.global_id, :type => 'never_expires'}
      expect(response).to be_success
      
      json = JSON.parse(response.body)
      expect(json['progress']).not_to eq(nil)
      Worker.process_queues
      expect(u.reload.never_expires?).to eq(true)
    end
    
    it "should let admins set a subscription to eval" do
      token_user
      u = User.create
      o = Organization.create(:admin => true, :settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, true)
      
      post :subscribe, params: {:user_id => u.global_id, :type => 'eval'}
      expect(response).to be_success
      
      json = JSON.parse(response.body)
      expect(json['progress']).not_to eq(nil)
      Worker.process_queues
      expect(u.reload.settings['subscription']['plan_id']).to eq('eval_monthly_free')
    end
    
    it "should not let admins set a subscription to gift_code" do
      token_user
      u = User.create
      o = Organization.create(:admin => true, :settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, true)
      
      post :subscribe, params: {:user_id => u.global_id, :type => 'gift_code', 'code' => 'asdf'}
      assert_unauthorized
    end

    it "should not let non-admins set a subscription to never_expires" do
      token_user
      post :subscribe, params: {:user_id => @user.global_id, :type => 'never_expires'}
      assert_unauthorized
    end
    
    it "should not let non-admins set a subscription to eval" do
      token_user
      post :subscribe, params: {:user_id => @user.global_id, :type => 'eval'}
      assert_unauthorized
    end
    
    it "should cancel any active subscription when admins set to free supporter" do
      token_user
      @user.update_subscription({
        'subscribe' => true,
        'plan_id' => 'monthly_6',
        'subscription_id' => 'asdf',
        'token_summary' => 'good_one'
      })
      expect(@user.full_premium?).to eq(true)

      o = Organization.create(:admin => true, :settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, true)
      
      post :subscribe, params: {:user_id => @user.global_id, :type => 'manual_supporter'}
      expect(response).to be_success
      
      json = JSON.parse(response.body)
      expect(json['progress']).not_to eq(nil)
      Worker.process_queues
      expect(@user.reload.settings['subscription']['plan_id']).to eq('slp_monthly_free')
      expect(@user.full_premium?).to eq(false)
      expect(@user.free_premium?).to eq(true)
    end
   
    it "should let admins add a premium voice" do
      token_user
      u = User.create
      o = Organization.create(:admin => true, :settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, true)
      
      post :subscribe, params: {:user_id => u.global_id, :type => 'add_voice'}
      expect(response).to be_success
      
      json = JSON.parse(response.body)
      expect(json['progress']).not_to eq(nil)
      Worker.process_queues
      expect(u.reload.settings['premium_voices']).to eq({'claimed' => [], 'allowed' => 1})
    end
    
    it "should not let non-admins add a premium voice" do
      token_user
      u = User.create
      
      post :subscribe, params: {:user_id => u.global_id, :type => 'add_voice'}
      assert_unauthorized
      
      expect(u.reload.settings['premium_voices']).to eq(nil)
    end
    
    it "should require api token for gift_code requests" do
      g = GiftPurchase.process_new({}, {
        'email' => 'bob@example.com',
        'seconds' => 3.years.to_i
      })
      @user = User.create
      exp = @user.expires_at
      
      post :subscribe, params: {:user_id => @user.global_id, :token => {'code' => g.code}, :type => 'gift_code'}
      assert_missing_token
    end
    
    it "should require api token for override requests" do
      @user = User.create
      u = User.create
      o = Organization.create(:admin => true, :settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, true)
      
      post :subscribe, params: {:user_id => u.global_id, :type => 'never_expires'}
      assert_missing_token
    end
    
    it "should allow updating a subscription with no api token, but a confirmation code" do
      @user = User.create
      p = Progress.create
      expect(Progress).to receive(:schedule).with(@user, :process_subscription_token, {'code' => 'abc'}, 'monthly_6').and_return(p)
      post :subscribe, params: {:user_id => @user.global_id, :confirmation => @user.registration_code, :token => {'code' => 'abc'}, :type => 'monthly_6'}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['progress']).not_to eq(nil)
    end
    
    it "should not allow updating a subscription with no api token and no confirmation code" do
      @user = User.create
      post :subscribe, params: {:user_id => @user.global_id, :confirmation => 'abc', :token => {'code' => 'abc'}, :type => 'monthly_6'}
      assert_missing_token
    end
  end
  
  describe "unsubscribe" do
    it "should require an api token" do
      delete :unsubscribe, params: {:user_id => 'asdf'}
      assert_missing_token
    end
    
    it "should require edit permissions" do
      token_user
      u = User.create
      delete :unsubscribe, params: {:user_id => u.global_id}
      assert_unauthorized
    end

    it "should schedule token processing" do
      token_user
      p = Progress.create
      expect(Progress).to receive(:schedule).with(@user, :process_subscription_token, 'token', 'unsubscribe').and_return(p)
      delete :unsubscribe, params: {:user_id => @user.global_id}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['progress']).not_to eq(nil)
    end
  end
  
  describe "claim_voice" do
    it "should require api token" do
      post :claim_voice, params: {:user_id => '1_99999'}
      assert_missing_token
    end
    
    it "should error on not found" do
      token_user
      post :claim_voice, params: {:user_id => 'abcdef'}
      assert_not_found('abcdef')
    end
    
    it "should require edit permissions" do
      token_user
      u = User.create
      post :claim_voice, params: {:user_id => u.global_id}
      assert_unauthorized
    end
    
    it "should return an error if add_voice fails" do
      token_user
      @user.settings['premium_voices'] = {'allowed' => 0}
      @user.save
      post :claim_voice, params: {:user_id => @user.global_id, :voice_id => 'acbdef'}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['error']).to eq('no more voices available')
    end
    
    it "should return success and add the voice if correct" do
      token_user
      @user.subscription_override('never_expires')
      post :claim_voice, params: {:user_id => @user.global_id, :voice_id => 'asdf'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq({'voice_added' => true, 'voice_id' => 'asdf'})
      @user.reload
      expect(@user.settings['premium_voices']['claimed']).to eq(['asdf'])
    end
    
    it "should generate a signed download url on success" do
      token_user
      @user.subscription_override('never_expires')
      expect(Uploader).to receive(:signed_download_url).with('asdf').and_return("asdfjkl")
      post :claim_voice, params: {:user_id => @user.global_id, :voice_id => 'asdf', :voice_url => 'asdf'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq({'voice_added' => true, 'voice_id' => 'asdf', 'download_url' => 'asdfjkl'})
    end
  end
  
  describe "rename" do
    it "should require api token" do
      post :rename, params: {:user_id => "1_1"}
      assert_missing_token
    end
    
    it "should error on not found" do
      token_user
      post :rename, params: {:user_id => "1_19999"}
      assert_not_found
    end

    it "should require edit permissions" do
      u = User.create
      token_user
      post :rename, params: {:user_id => u.global_id}
      assert_unauthorized
    end
    
    it "should rename the board" do
      token_user
      post :rename, params: {:user_id => @user.global_id, :old_key => @user.user_name, :new_key => "wilford"}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq({'rename' => true, 'key' => "wilford"})
    end

    it "should require the correct old_key" do
      token_user
      post :rename, params: {:user_id => @user.global_id, :old_key => @user.user_name + "asdf", :new_key => "wilford"}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json).not_to eq(nil)
      expect(json['error']).to eq('user rename failed')
    end
    
    it "should require a valid new_key" do
      token_user
      post :rename, params: {:user_id => @user.global_id, :old_key => @user.user_name}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json).not_to eq(nil)
      expect(json['error']).to eq('user rename failed')
    end
    
    it "should report if there was a new_key name collision" do
      token_user
      u2 = User.create
      post :rename, params: {:user_id => @user.global_id, :old_key => @user.user_name, :new_key => u2.user_name}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json).not_to eq(nil)
      expect(json['error']).to eq('user rename failed')
      expect(json['collision']).to eq(true)
    end
  end

  describe "activate_button" do
    it "should require an api token" do
      post :activate_button, params: {:user_id => 'asdf', :board_id => 'asdf'}
      assert_missing_token
    end
    
    it "should require a valid user" do
      token_user
      post :activate_button, params: {:user_id => 'asdf', :board_id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require an authorized user" do
      token_user
      u = User.create
      post :activate_button, params: {:user_id => u.global_id, :board_id => 'asdf'}
      assert_unauthorized
    end
    
    it "should require a valid board" do
      token_user
      post :activate_button, params: {:user_id => @user.global_id, :board_id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require an authorized board" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      post :activate_button, params: {:user_id => @user.global_id, :board_id => b.global_id}
      assert_unauthorized
    end
    
    it "should require a valid button" do
      token_user
      b = Board.create(:user => @user)
      post :activate_button, params: {:user_id => @user.global_id, :board_id => b.global_id}
      assert_error('button not found')
    end
    
    it "should require an integration button" do
      token_user
      b = Board.create(:user => @user)
      b.settings['buttons'] = [{
        'id' => '1'
      }]
      b.save
      post :activate_button, params: {:user_id => @user.global_id, :board_id => b.global_id, :button_id => '1'}
      assert_error('button integration not configured')
    end
    
    it "should return a progress record" do
      token_user
      ui = UserIntegration.create(:user => @user)
      b = Board.create(:user => @user)
      b.settings['buttons'] = [{
        'id' => '1',
        'integration' => {'user_integration_id' => ui.global_id}
      }]
      b.save
      post :activate_button, params: {:user_id => @user.global_id, :board_id => b.global_id, :button_id => '1'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['progress']['id']).to_not eq(nil)
      id = json['progress']['id']
      progress = Progress.find_by_path(id)
      expect(progress.settings['arguments']).to eq(['button_action', {'user_id' => @user.global_id, 'immediate' => true, 'associated_user_id' => nil, 'button_id' => '1'}])
      expect(progress.settings['class']).to eq('Board')
      expect(progress.settings['method']).to eq('notify')
    end
    
    it "should attach an associated user if specified and authorized" do
      token_user
      ui = UserIntegration.create(:user => @user)
      b = Board.create(:user => @user)
      b.settings['buttons'] = [{
        'id' => '1',
        'integration' => {'user_integration_id' => ui.global_id}
      }]
      b.save
      post :activate_button, params: {:user_id => @user.global_id, :board_id => b.global_id, :button_id => '1', :associated_user_id => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['progress']['id']).to_not eq(nil)
      id = json['progress']['id']
      progress = Progress.find_by_path(id)
      expect(progress.settings['arguments']).to eq(['button_action', {'user_id' => @user.global_id, 'immediate' => true, 'associated_user_id' => @user.global_id, 'button_id' => '1'}])
      expect(progress.settings['class']).to eq('Board')
      expect(progress.settings['method']).to eq('notify')
    end
    
    it "should not attach an associated user if specified but not authorized" do
      token_user
      u = User.create
      ui = UserIntegration.create(:user => @user)
      b = Board.create(:user => @user)
      b.settings['buttons'] = [{
        'id' => '1',
        'integration' => {'user_integration_id' => ui.global_id}
      }]
      b.save
      post :activate_button, params: {:user_id => @user.global_id, :board_id => b.global_id, :button_id => '1', :associated_user_id => u.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['progress']['id']).to_not eq(nil)
      id = json['progress']['id']
      progress = Progress.find_by_path(id)
      expect(progress.settings['arguments']).to eq(['button_action', {'user_id' => @user.global_id, 'immediate' => true, 'associated_user_id' => nil, 'button_id' => '1'}])
      expect(progress.settings['class']).to eq('Board')
      expect(progress.settings['method']).to eq('notify')
    end
  end
  
  describe 'GET supervisors' do
    it "should require a valid token" do
      get 'supervisors', params: {'user_id' => 'asdf'}
      assert_missing_token
    end
    
    it "should require a valid record" do
      token_user
      get 'supervisors', params: {'user_id' => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      u = User.create
      get 'supervisors', params: {'user_id' => u.global_id}
      assert_unauthorized
    end
    
    it "should return a paginated result" do
      token_user
      u = User.create
      User.link_supervisor_to_user(u, @user)
      get 'supervisors', params: {'user_id' => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['meta']['more']).to eq(false)
      expect(json['user'].length).to eq(1)
      expect(json['user'][0]['id']).to eq(u.global_id)
    end
  end
  
  describe 'GET supervisees' do
    it "should require a valid token" do
      get 'supervisees', params: {'user_id' => 'asdf'}
      assert_missing_token
    end
    
    it "should require a valid record" do
      token_user
      get 'supervisees', params: {'user_id' => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      u = User.create
      get 'supervisees', params: {'user_id' => u.global_id}
      assert_unauthorized
    end
    
    it "should return a paginated result" do
      token_user
      u = User.create
      User.link_supervisor_to_user(@user, u)
      get 'supervisees', params: {'user_id' => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['meta']['more']).to eq(false)
      expect(json['user'].length).to eq(1)
      expect(json['user'][0]['id']).to eq(u.global_id)
    end
  end
  
  describe "GET 'sync_stamp'" do
    it "should require an access token" do
      get 'sync_stamp', params: {'user_id' => 'asdf'}
        assert_missing_token
    end
    
    it "should require a valid user" do
      token_user
      get 'sync_stamp', params: {'user_id' => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      u = User.create
      User.link_supervisor_to_user(@user, u, nil, true)
      get 'sync_stamp', params: {'user_id' => u.global_id}
      assert_unauthorized
    end
    
    it "should return the user's sync stamp" do
      token_user
      get 'sync_stamp', params: {'user_id' => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['sync_stamp']).to eq(@user.updated_at.utc.iso8601)
    end
  end
  
  describe "translate" do
    it "should require an access token" do
      post 'translate', params: {:user_id => 'asdf'}
      assert_missing_token
    end
    
    it "should require a valid user" do
      token_user
      post 'translate', params: {:user_id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require permission" do
      token_user
      u = User.create
      post 'translate', params: {:user_id => u.global_id}
      assert_unauthorized
    end
    
    it "should call translate action and return the result" do
      token_user
      words = ['a', 'b', 'c']
      expect(WordData).to receive(:translate_batch).with(words.map{|w| {:text => w} }, 'en', 'es').and_return({a: 'a'})
      post 'translate', params: {:user_id => @user.global_id, :words => words, :source_lang => 'en', :destination_lang => 'es'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq({'a' => 'a'})
    end
  end
  
  describe "board_revisions" do
    it "should require an access token" do
      get 'board_revisions', params: {:user_id => '1_000'}
      assert_missing_token
    end
    
    it "should require a valid user" do
      token_user
      get 'board_revisions', params: {:user_id => '1_000'}
      assert_not_found('1_000')
    end
    
    it "should require permission" do
      token_user
      u = User.create
      get 'board_revisions', params: {:user_id => u.global_id}
      assert_unauthorized
    end
    
    it "should return revisions for all home board links and sidebar board links" do
      token_user
      b1 = Board.create(:user => @user)
      b2 = Board.create(:user => @user)
      b3 = Board.create(:user => @user)
      b4 = Board.create(:user => @user)
      b5 = Board.create(:user => @user)
      b1.settings['buttons'] = [{'id' => 1, 'load_board' => {'id' => b2.global_id}}]
      b1.instance_variable_set('@buttons_changed', true)
      b1.save
      b2.settings['buttons'] = [{'id' => 1, 'load_board' => {'id' => b3.global_id}}]
      b2.instance_variable_set('@buttons_changed', true)
      b2.save
      @user.settings['preferences']['home_board'] = {'id' => b1.global_id, 'key' => b1.key}

      @user.settings['preferences']['sidebar_boards'] = [{'key' => b4.key}]
      @user.save
      Worker.process_queues
      Worker.process_queues
      expect(b1.reload.settings['downstream_board_ids'].sort).to eq([b2.global_id, b3.global_id].sort)
      get 'board_revisions', params: {:user_id => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      hash = {}
      hash[b1.global_id] = b1.reload.current_revision
      hash[b1.key] = b1.current_revision
      hash[b2.global_id] = b2.reload.current_revision
      hash[b2.key] = b2.current_revision
      hash[b3.global_id] = b3.reload.current_revision
      hash[b3.key] = b3.current_revision
      hash[b4.global_id] = b4.reload.current_revision
      hash[b4.key] = b4.current_revision
      expect(json).to eq(hash)
    end
  end
  
  describe "places" do
    it "should require an access token" do
      get 'places', params: {:user_id => 'asdf'}
      assert_missing_token
    end
    
    it "should require a valid user" do
      token_user
      get 'places', params: {:user_id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      u = User.create
      get 'places', params: {:user_id => u.global_id}
      assert_unauthorized
    end
    
    it "should return a list of places" do
      token_user
      expect(Geolocation).to receive(:find_places).with(nil, nil).and_return([])
      get 'places', params: {:user_id => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq([])
    end
  end
  
  describe "daily_use" do
    it 'should require an access token' do
      get 'daily_use', params: {:user_id => 'asdf'}
      assert_missing_token
    end
    
    it 'should require a valid user' do
      token_user
      get 'daily_use', params: {:user_id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it 'should require admin permission' do
      token_user
      get 'daily_use', params: {:user_id => @user.global_id}
      assert_unauthorized
    end
    
    it 'should return nothing if data not available' do
      token_user
      o = Organization.create(:admin => true)
      o.add_manager(@user.user_name, true)
      get 'daily_use', params: {:user_id => @user.global_id}
      assert_error('no data available', 400)
    end

    it 'should return data if available' do
      token_user
      d = Device.create(:user => @user)
      o = Organization.create(:admin => true)
      o.add_manager(@user.user_name, true)
      log = LogSession.process_as_follow_on({
        'type' => 'daily_use',
        'events' => [
          {'date' => '2016-01-01', 'active' => true},
          {'date' => Date.today.iso8601, 'active' => true}
        ]
      }, {:device => d, :user => @user, :author => @user})
      get 'daily_use', params: {:user_id => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['log']).to_not eq(nil)
      expect(json['log']['id']).to eq(log.global_id)
      expect(json['log']['daily_use']).to eq([{
        'date' => Date.today.iso8601, 'active' => true, 'activity_level' => nil
      }])
    end
  end
  
  describe "history" do
    it 'should require api token' do
      get 'history', :params => {'user_id' => 'asdf'}
      assert_missing_token
    end
    
    it 'should require a valid user' do
      token_user
      get 'history', :params => {'user_id' => 'asdf'}
      assert_not_found('asdf')
    end
    
    it 'should require admin authorization' do
      token_user
      get 'history', :params => {'user_id' => @user.global_id}
      assert_unauthorized
    end
    
    it 'should return a list of versions' do
      token_user
      o = Organization.create(:admin => true)
      o.add_manager(@user.user_name, true)
      u = User.create
      get 'history', :params => {'user_id' => u.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['userversion']).to eq([])
    end
  end
  
  describe "core_lists" do
    it "should require api token" do
      get 'core_lists', params: {'user_id' => 'asdf'}
      assert_missing_token
    end
     
    it "should require a valid user" do
      token_user
      get 'core_lists', params: {'user_id' => 'asdf'}
      assert_not_found('asdf')
    end
     
    it "should require supervise authorization for a valid user" do
      token_user
      u = User.create
      get 'core_lists', params: {'user_id' => u.global_id}
      assert_unauthorized
    end
     
    it "should return core lists" do
      token_user
      u = User.create
      User.link_supervisor_to_user(@user, u, nil, false)
      expect(u.allows?(@user, 'edit')).to eq(false)
      expect(u.allows?(@user, 'supervise')).to eq(true)
      get 'core_lists', params: {'user_id' => u.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to_not eq(nil)
      expect(json['for_user']).to_not eq(nil)
      expect(json['defaults'].length).to be > 0
    end
     
    it "should return successfully for the 'none' user" do
      token_user
      get 'core_lists', params: {'user_id' => 'none'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to_not eq(nil)
      expect(json['for_user']).to eq(nil)
      expect(json['defaults'].length).to be > 0
    end
     
    it "should return a user's core lists" do
      token_user
      ui = UserIntegration.create(:template => true, :integration_key => 'core_word_list')
      ui2 = UserIntegration.create(:template_integration_id => ui.id, :user => @user)
      ui2.settings['core_word_list'] = {
        id: 'bacon',
        words: ['a', 'b', 'c', 'd']
      }
      ui2.save
      get 'core_lists', params: {'user_id' => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to_not eq(nil)
      expect(json['for_user']).to eq(['a', 'b', 'c', 'd'])
      expect(json['defaults'].length).to be > 0
    end
    
    it "should include fringe lists" do
      token_user
      ui = UserIntegration.create(:template => true, :integration_key => 'core_word_list')
      ui2 = UserIntegration.create(:template_integration_id => ui.id, :user => @user)
      ui2.settings['core_word_list'] = {
        id: 'bacon',
        words: ['a', 'b', 'c', 'd']
      }
      ui2.save
      get 'core_lists', params: {'user_id' => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['reachable_fringe_for_user']).to eq([])
    end
  end
  
  describe "message_bank_suggestions" do
    it "should require api token" do
      get 'message_bank_suggestions', params: {'user_id' => 'asdf'}
      assert_missing_token
    end
    
    it "should return a list" do
      token_user
      get 'message_bank_suggestions', params: {'user_id' => 'asdf'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json.length).to be > 0
      expect(json[0]['id']).to eq('boston_childrens')
    end
  end
  
  describe "update_core_list" do
    it "should require api token" do
      put 'update_core_list', params: {'user_id' => 'asdf'}
      assert_missing_token
    end
    
    it "should require a valid user" do
      token_user
      put 'update_core_list', params: {'user_id' => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      u = User.create
      User.link_supervisor_to_user(@user, u, nil, false)
      expect(u.allows?(@user, 'edit')).to eq(false)
      expect(u.allows?(@user, 'supervise')).to eq(true)
      put 'update_core_list', params: {'user_id' => u.global_id}
      assert_unauthorized
    end
    
    it "should error if no template is defined" do
      token_user
      put 'update_core_list', params: {'user_id' => @user.global_id, 'id' => 'bacon', 'words' => ['a', 'b', 'c']}
      assert_error('no core word list integration defined')
    end
    
    it "should set the user's core list" do
      token_user
      ui = UserIntegration.create(:template => true, :integration_key => 'core_word_list')
      put 'update_core_list', params: {'user_id' => @user.global_id, 'id' => 'bacon', 'words' => ['a', 'b', 'c']}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq({'updated' => true, 'words' => {'id' => 'bacon', 'words' => ['a', 'b', 'c']}})
      ui = UserIntegration.find_by(:user_id => @user.id, :template_integration_id => ui.id)
      expect(ui).to_not eq(nil)
      expect(ui.settings).to_not eq(nil)
      expect(ui.settings['core_word_list']).to eq({'id' => 'bacon', 'words' => ['a', 'b', 'c']})
    end
  end
  
  describe "protected_image" do
    it 'should not require an access token' do
      get 'protected_image', params: {'user_id' => 'asdf', 'library' => 'whatever', 'image_id' => '123'}
      expect(response).to be_redirect
    end
    
    it 'should redirect without a valid user' do
      get 'protected_image', params: {'user_id' => 'asdf', 'library' => 'whatever', 'image_id' => '123'}
      expect(response).to be_redirect
      expect(response.location).to eq('http://test.host/images/square.svg')
    end

    it 'should stream to a fallback url if defined' do
      res = OpenStruct.new(headers: {'Content-Type' => 'image/png', body: 'asdf'})
      expect(Typhoeus).to receive(:get).with('http://lessonpix.com/drawings/123/100x100/123.png').and_return(res)
      get 'protected_image', params: {'user_id' => 'asdf', 'library' => 'lessonpix', 'image_id' => '123'}
      expect(response).to be_success
      expect(response.headers['Content-Type']).to eq('image/png')
      expect(response.headers['Content-Disposition']).to eq('inline')
    end
    
    it 'should redirect if no match found' do
      u = User.create
      expect(Uploader).to receive(:found_image_url).with('123', 'good_library', u).and_return(nil).at_least(1).times
      get 'protected_image', params: {'user_id' => u.global_id, 'user_token' => u.user_token, 'library' => 'good_library', 'image_id' => '123'}
      expect(response).to be_redirect
      expect(response.location).to eq('http://test.host/images/error.png')
    end

    it 'should stream a fallback url if defined if no match found' do
      u = User.create
      expect(Uploader).to receive(:found_image_url).with('123', 'lessonpix', u).and_return(nil).at_least(1).times
      res = OpenStruct.new(headers: {'Content-Type' => 'image/png', body: 'asdf'})
      expect(Typhoeus).to receive(:get).with('http://lessonpix.com/drawings/123/100x100/123.png').and_return(res)
      get 'protected_image', params: {'user_id' => u.global_id, 'user_token' => u.user_token, 'library' => 'lessonpix', 'image_id' => '123'}
      expect(response).to be_success
      expect(response.headers['Content-Type']).to eq('image/png')
      expect(response.headers['Content-Disposition']).to eq('inline')
    end
    
    it 'should return the correct search result' do
      u = User.create
      expect(Uploader).to receive(:found_image_url).with('123', 'good_library', u).and_return('http://www.example.com/pic.png')
      res = OpenStruct.new(headers: {'Content-Type' => 'image/png', body: 'asdf'})
      expect(Typhoeus).to receive(:get).with('http://www.example.com/pic.png').and_return(res)
      get 'protected_image', params: {'user_id' => u.global_id, 'user_token' => u.user_token, 'library' => 'good_library', 'image_id' => '123'}
      expect(response).to be_success
      expect(response.headers['Content-Type']).to eq('image/png')
      expect(response.headers['Content-Disposition']).to eq('inline')
    end
    
    it "should handle a single redirect if defined" do
      u = User.create
      expect(Uploader).to receive(:found_image_url).with('123', 'good_library', u).and_return('http://www.example.com/pic.png')
      res1 = OpenStruct.new(headers: {'Location' => 'http://www.example.com/redirect/pic.png'})
      res2 = OpenStruct.new(headers: {'Content-Type' => 'image/png', body: 'asdf'})
      expect(Typhoeus).to receive(:get).with('http://www.example.com/pic.png').and_return(res1)
      expect(Typhoeus).to receive(:get).with('http://www.example.com/redirect/pic.png').and_return(res2)
      get 'protected_image', params: {'user_id' => u.global_id, 'user_token' => u.user_token, 'library' => 'good_library', 'image_id' => '123'}
      expect(response).to be_success
      expect(response.headers['Content-Type']).to eq('image/png')
      expect(response.headers['Content-Disposition']).to eq('inline')
    end
    
    it 'should redirect to the cached copy if found' do
      bi = ButtonImage.create(url: 'coughdrop://protected_image/lessonpix/12345', settings: {'cached_copy_url' => 'http://www.example.com/pic.png'})
      u = User.create
      expect(Uploader).to receive(:lessonpix_credentials).with(u).and_return({})
      get 'protected_image', params: {'user_id' => u.global_id, 'user_token' => u.user_token, 'library' => 'lessonpix', 'image_id' => '12345'}
      expect(response).to be_redirect
      expect(response.location).to eq('http://www.example.com/pic.png')
    end
  end
end
