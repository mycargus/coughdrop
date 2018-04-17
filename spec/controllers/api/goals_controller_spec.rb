require 'spec_helper'

describe Api::GoalsController, type: :controller do
  describe "index" do
    it "should not require api token" do
      get :index, params: {:template_header => 1}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal']).to eq([])
    end
    
    it "should list template_header goals" do
      g = UserGoal.create(:template_header => true)
      get :index, params: {:template_header => 1}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal'].length).to eq(1)
      expect(json['goal'][0]['id']).to eq(g.global_id)
    end
    
    it "should require permission for user goals" do
      u = User.create
      token_user
      get :index, params: {:user_id => u.global_id}
      assert_unauthorized
    end
    
    it "should list user goals if authorized" do
      token_user
      g = UserGoal.create(:user => @user)
      get :index, params: {:user_id => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal'].length).to eq(1)
      expect(json['goal'][0]['id']).to eq(g.global_id)
    end
    
    it "should paginate results" do
      token_user
      50.times do |i|
        UserGoal.create(:user => @user)
      end
      get :index, params: {:user_id => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal'].length).to eq(30)
      expect(json['meta']['more']).to eq(true)
    end
    
    it "should list goals for a specific template when authorized" do
      token_user
      g = UserGoal.create(:user => @user, :settings => {'template_header_id' => 'self'}, :template_header => true)
      Worker.process_queues
      expect(g.reload.settings['template_header_id']).to eq(g.global_id)
      get :index, params: {:template_header_id => g.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal'].length).to eq(1)
    end
    
    it "should list a user's template if authorized" do
      token_user
      g = UserGoal.create(:user => @user, :template => true)
      get :index, params: {:user_id => @user.global_id, :template => true}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal'].length).to eq(1)
      expect(json['goal'][0]['id']).to eq(g.global_id)
    end
    
    it "should allow filtering to global goals" do
      token_user
      g = UserGoal.create(:user => @user, :global => true)
      g2 = UserGoal.create(:user => @user)
      get :index, params: {:global => true}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal'].length).to eq(1)
      expect(json['goal'][0]['id']).to eq(g.global_id)
    end
  end
  
  describe "show" do
    it "should require api token" do
      get :show, params: {:id => 'asdf'}
      assert_missing_token
    end
    
    it "should require valid record" do
      token_user
      get :show, params: {:id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require permission" do
      token_user
      u = User.create
      g = UserGoal.create(:user => u)
      get :show, params: {:id => g.global_id}
      assert_unauthorized
    end
    
    it "should return goal" do
      token_user
      g = UserGoal.create(:user => @user)
      get :show, params: {:id => g.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal']['id']).to eq(g.global_id)
    end
  end

  describe "create" do
    it "should require api token" do
      post :create
      assert_missing_token
    end
    
    it "should require valid user_id" do
      token_user
      post :create, params: {:goal => {'user_id' => 'asdf'}}
      assert_not_found('asdf')
    end
    
    it "should require permission" do
      token_user
      u = User.create
      post :create, params: {:goal => {'user_id' => u.global_id}}
      assert_unauthorized
    end
    
    it "should create goal" do
      token_user
      post :create, params: {:goal => {'user_id' => @user.global_id, 'summary' => 'cool goal'}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal']['id']).to_not be_nil
      expect(json['goal']['summary']).to eq('cool goal')
    end
    
    it "should require admin permission to create a template header" do
      token_user
      post :create, params: {:goal => {'template_header' => true, 'summary' => 'template goal'}}
      assert_unauthorized
      o = Organization.create(:admin => true, :settings => {'total_licenses' => 1})
      o.add_manager(@user.user_name, true)
      post :create, params: {:goal => {'template_header' => true, 'summary' => 'template goal'}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal']['id']).to_not be_nil
    end
    
    it "should default to the api_user when creating a goal" do
      token_user
      post :create, params: {:goal => {'summary' => 'cool goal'}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal']['id']).to_not be_nil
      expect(json['goal']['author']['id']).to eq(@user.global_id)
    end
    
    it "should not allow a basic api token to create a goal" do
      token_user(['read_profile'])
      post :create, params: {:goal => {'summary' => 'cool goal'}}
      assert_unauthorized
    end

    it "should allow a supervising token to create a goal" do
      token_user(['basic_supervision'])
      post :create, params: {:goal => {'summary' => 'cool goal'}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal']['id']).to_not be_nil
    end
    
    it "should auto-expire a token with the same external_id" do
      token_user
      eid = 'some:bucket'
      goal = UserGoal.create(user: @user, active: true)
      goal.settings['external_id'] = eid
      goal.save!
      expect(goal.active).to eq(true)
      post :create, params: {:goal => {'user_id' => @user.global_id, 'summary' => 'cool goal', 'external_id' => eid}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal']['id']).to_not be_nil
      expect(json['goal']['summary']).to eq('cool goal')
      expect(goal.reload.active).to eq(true)
      Worker.process_queues
      expect(goal.reload.active).to eq(false)
    end
  end

  describe "update" do
    it "should require api token" do
      put :update, params: {:id => 'asdf'}
      assert_missing_token
    end
    
    it "should require existing record" do
      token_user
      put :update, params: {:id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require permission" do
      token_user
      u = User.create
      g = UserGoal.create(:user => u)
      put :update, params: {:id => g.global_id}
      assert_unauthorized
    end
    
    it "should update the record" do
      token_user
      g = UserGoal.create(:user => @user)
      put :update, params: {:id => g.global_id, :goal => {'summary' => 'better goal'}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal']['id']).to eq(g.global_id)
      expect(json['goal']['summary']).to eq('better goal')
    end
    
    it "should allow those with non-edit permissions to comment but nothing else" do
      token_user
      u = User.create
      User.link_supervisor_to_user(@user, u, nil, false)
      g = UserGoal.create(:user => u)
      put :update, params: {:id => g.global_id, :goal => {'summary' => 'dumb name', 'comment' => {'text' => 'hey yo'}}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal']['summary']).to eq('user goal')
      expect(json['goal']['comments'].length).to eq(1)
      expect(json['goal']['comments'][0]['text']).to eq('hey yo')
      expect(json['goal']['comments'][0]['user']['user_name']).to eq(@user.user_name)
    end
    
    it "should not allow a supervision api token to update a goal" do
      token_user(['read_profile', 'basic_supervision'])
      u = User.create
      User.link_supervisor_to_user(@user, u, nil, false)
      g = UserGoal.create(:user => u)
      put :update, params: {:id => g.global_id, :goal => {'summary' => 'dumb name', 'comment' => {'text' => 'hey yo'}}}
      assert_unauthorized
    end
  end

  describe "destroy" do
    it "should require api token" do
      delete :destroy, params: {:id => 'asdf'}
      assert_missing_token
    end
    
    it "should require existing record" do
      token_user
      delete :destroy, params: {:id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require permission" do
      token_user
      u = User.create
      User.link_supervisor_to_user(@user, u, nil, false)
      g = UserGoal.create(:user => u)
      delete :destroy, params: {:id => g.global_id}
      assert_unauthorized
    end
    
    it "should delete the record" do
      token_user
      u = User.create
      User.link_supervisor_to_user(@user, u, nil, true)
      g = UserGoal.create(:user => u)
      delete :destroy, params: {:id => g.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['goal']['id']).to eq(g.global_id)
      expect(UserGoal.find_by_global_id(g.global_id)).to eq(nil)
    end
  end
end
