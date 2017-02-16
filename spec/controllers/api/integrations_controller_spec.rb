require 'spec_helper'

describe Api::IntegrationsController, :type => :controller do
  describe "get 'index'" do
    it "should require an api token" do
      get 'index', params: {'user_id' => 'asdf'}
      assert_missing_token
    end
    
    it "should error if the user doesn't exist" do
      token_user
      get 'index', params: {'user_id' => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should error if not authorized" do
      token_user
      u = User.create
      get 'index', params: {'user_id' => u.global_id}
      assert_unauthorized
    end
    
    it "should return a paginated list" do
      token_user
      ui = UserIntegration.create(:user_id => @user.id)
      get 'index', params: {'user_id' => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to_not eq(nil)
      expect(json['integration']).to_not eq(nil)
      expect(json['integration'].length).to eq(1)
      expect(json['integration'][0]['id']).to eq(ui.global_id)
      expect(json['meta']).to_not eq(nil)
    end
  end
  
  describe "post 'create'" do
    it "should require an api token" do
      post 'create'
      assert_missing_token
    end
    
    it "should error if the user doesn't exist" do
      token_user
      post 'create', params: {'integration' => {'user_id' => 'asdf'}}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      u = User.create
      post 'create', params: {'integration' => {'user_id' => u.global_id}}
      assert_unauthorized
    end
    
    it "should create the record" do
      token_user
      post 'create', params: {'integration' => {'user_id' => @user.global_id, 'name' => 'test integration'}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to_not eq(nil)
      expect(json['integration']['id']).to_not eq(nil)
      expect(json['integration']['name']).to eq('test integration')
    end
    
    it 'should update an existing integration if already set for user/key pair' do
      token_user
      template = UserIntegration.create(template: true, integration_key: 'something_cool', settings: {'icon_url' => 'http://www.example.com/icon.png'})
      ui = UserIntegration.create(user: @user, template_integration: template)
      post 'create', params:{'integration' => {'user_id' => @user.global_id, 'name' => 'good stuff', 'integration_key' => 'something_cool'}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['integration']['id']).to eq(ui.global_id)
      expect(json['integration']['name']).to eq('good stuff')
      expect(json['integration']['icon_url']).to eq('http://www.example.com/icon.png')
      expect(json['integration']['template_key']).to eq('something_cool')
    end
  end
  
  describe "put 'update'" do
    it "should require an api token" do
      put 'update', params: {'id' => 'asdf'}
      assert_missing_token
    end
    
    it "should error if the record doesn't exist" do
      token_user
      put 'update', params: {'id' => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      u = User.create
      ui = UserIntegration.create(:user_id => u.id)
      put 'update', params: {'id' => ui.global_id}
      assert_unauthorized
    end
    
    it "should update the record" do
      token_user
      ui = UserIntegration.create(:user_id => @user.id)
      put 'update', params: {'id' => ui.global_id, 'integration' => {'name' => 'new name'}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to_not eq(nil)
      expect(json['integration']['id']).to eq(ui.global_id)
      expect(json['integration']['name']).to eq('new name')
    end
  end
  
  describe "delete 'destroy'" do
    it "should require an api token" do
      delete 'destroy', params: {'id' => 'asdf'}
      assert_missing_token
    end
    
    it "should error if the record doesn't exist" do
      token_user
      delete 'destroy', params: {'id' => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      u = User.create
      ui = UserIntegration.create(:user_id => u.id)
      delete 'destroy', params: {'id' => ui.global_id}
      assert_unauthorized
    end
    
    it "should delete the record" do
      token_user
      ui = UserIntegration.create(:user_id => @user.id)
      delete 'destroy', params: {'id' => ui.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to_not eq(nil)
      expect(json['integration']['id']).to eq(ui.global_id)
    end
  end
end
