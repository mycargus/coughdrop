require 'spec_helper'

describe Api::ButtonSetsController, :type => :controller do
  describe "show" do
    it "should not require api token" do
      get :show, params: {:id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require existing object" do
      token_user
      get :show, params: {:id => '1_19999'}
      assert_not_found('1_19999')
    end

    it "should require authorization" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      bs = BoardDownstreamButtonSet.update_for(b.global_id)
      get :show, params: {:id => b.global_id}
      assert_unauthorized
    end
    
    it "should return a json response" do
      token_user
      b = Board.create(:user => @user)
      bs = BoardDownstreamButtonSet.update_for(b.global_id)
      get :show, params: {:id => b.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['buttonset']['id']).to eq(b.global_id)
      expect(json['buttonset']['buttons']).to eq([])
    end
  end
  
  describe "index" do
    it "should require api token" do
      get :index
      assert_missing_token
    end
    
    it "should require valid user" do
      token_user
      get :index, params: {:user_id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      u = User.create
      get :index, params: {:user_id => u.global_id}
      assert_unauthorized
    end
    
    it "should return a paginated list" do
      token_user
      b = Board.create(:user => @user)
      bs = BoardDownstreamButtonSet.update_for(b.global_id)
      @user.settings['preferences']['home_board'] = {'id' => b.global_id}
      @user.save
      get :index, params: {:user_id => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['buttonset'].length).to eq(1)
      expect(json['buttonset'][0]['id']).to eq(b.global_id)
      expect(json['meta']['offset']).to eq(0)
    end
  end

  describe "generate" do
    it "should require an api token" do
      post :generate, params: {'id' => 'asdf'}
      assert_missing_token
    end

    it "should require a valid board" do
      token_user
      post :generate, params: {'id' => 'asdf'}
      assert_not_found('asdf')
    end

    it "should require permissions" do
      token_user
      u = User.create
      b = Board.create(user: u)
      post :generate, params: {'id' => b.global_id}
      assert_unauthorized
    end

    it "should return exists message if true" do
      token_user
      b = Board.create(user: @user)
      BoardDownstreamButtonSet.update_for(b.global_id,)
      post :generate, params: {'id' => b.global_id}
      json = assert_success_json
      expect(json).to eq({'exists' => true, 'id' => b.global_id})
    end

    it "should return a progress response if not yet generated" do
      token_user
      b = Board.create(user: @user)
      post :generate, params: {'id' => b.global_id}
      json = assert_success_json
      expect(json['progress']).to_not eq(nil)
      p = Progress.find_by_global_id(json['progress']['id'])
      expect(p.settings['class']).to eq('BoardDownstreamButtonSet')
      expect(p.settings['method']).to eq('update_for')
      expect(p.settings['arguments']).to eq([b.global_id, true])
    end
  end
end
