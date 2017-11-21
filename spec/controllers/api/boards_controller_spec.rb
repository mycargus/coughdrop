require 'spec_helper'

describe Api::BoardsController, :type => :controller do
  describe "index" do
    it "should not require api token" do
      get :index
      expect(response).to be_success
    end
    
    it "should filter by user_id" do
      u = User.create(:settings => {:public => true})
      b = Board.create(:user => u, :public => true)
      b2 = Board.create(:user => u)
      get :index, params: {:user_id => u.global_id, :public => true}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(1)
      expect(json['board'][0]['id']).to eq(b.global_id)
    end
    
    it "should require view_detailed permissions when filtering by user_id" do
      u = User.create
      get :index, params: {:user_id => u.global_id}
      assert_unauthorized

      get :index, params: {:user_id => u.global_id, :public => true}
      assert_unauthorized
    end
    
    it "should require edit permissions when filtering by user_id unless public" do
      u = User.create(:settings => {:public => true})
      get :index, params: {:user_id => u.global_id}
      assert_unauthorized
      
      get :index, params: {:user_id => u.global_id, :public => true}
      expect(response).to be_success
    end
    
    it "should allow filtering by user_id and private if authorized" do
      token_user
      @user.settings['public'] = true
      @user.save
      b = Board.create(:user => @user, :public => true)
      b2 = Board.create(:user => @user)
      get :index, params: {:user_id => @user.global_id, :private => true}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(1)
      expect(json['board'][0]['id']).to eq(b2.global_id)
    end
    
    it "should return only personal or public boards if authorized" do
      token_user
      b1 = Board.create(:user => @user)
      u2 = User.create
      b2 = Board.create(:user => u2)
      u3 = User.create
      b3 = Board.create(:user => u3, :public => true)
      @user.settings['starred_board_ids'] = [b1.global_id, b2.global_id, b3.global_id]
      @user.save
      get :index, params: {:user_id => @user.global_id, :starred => true}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(2)
      expect(json['board'].map{|b| b['id'] }).to be_include(b1.global_id)
      expect(json['board'].map{|b| b['id'] }).to be_include(b3.global_id)
      expect(json['board'].map{|b| b['id'] }).not_to be_include(b2.global_id)
    end
    
    it "should always filter by public when user_id is not provided" do
      u = User.create(:settings => {:public => true})
      b = Board.create(:user => u, :public => true)
      b2 = Board.create(:user => u)
      get :index
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(1)
      expect(json['board'][0]['id']).to eq(b.global_id)
    end
    
    it "should filter by a key" do
      u = User.create(:settings => {:public => true})
      b = Board.create(:user => u, :public => true)
      get :index, params: {:key => b.key}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(1)
      expect(json['board'][0]['id']).to eq(b.global_id)
    end
    
    it "should check for a user-owned board with the key name if valid access_token" do
      token_user
      @user.settings['public'] = true
      @user.save
      b = Board.create(:user => @user, :public => true)
      get :index, params: {:key => b.key.split(/\//)[1]}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(1)
      expect(json['board'][0]['id']).to eq(b.global_id)
    end
    
    it "should search by query string" do
      u = User.create(:settings => {:public => true})
      b = Board.create(:user => u, :public => true, :settings => {'name' => "one two three"})
      b2 = Board.create(:user => u, :public => true, :settings => {'name' => "four five six"})
      get :index, params: {:q => "two"}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(1)
      expect(json['board'][0]['id']).to eq(b.global_id)

      get :index, params: {:q => "six"}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(1)
      expect(json['board'][0]['id']).to eq(b2.global_id)
    end
    
    it "should search private boards by query string" do
      token_user
      b = Board.create(:user => @user, :settings => {'name' => "one two three"})
      b2 = Board.create(:user => @user, :settings => {'name' => "four five six"})
      get :index, params: {:user_id => @user.global_id, :q => "two"}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(1)
      expect(json['board'][0]['id']).to eq(b.global_id)

      get :index, params: {:user_id => @user.global_id, :q => "six"}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(1)
      expect(json['board'][0]['id']).to eq(b2.global_id)
    end
    
    it "should allow sorting by popularity or home_popularity" do
      u = User.create(:settings => {:public => true})
      b = Board.create(:user => u, :public => true)
      Board.where(:id => b.id).update_all({:home_popularity => 3, :popularity => 1})
      b2 = Board.create(:user => u, :public => true)
      Board.where(:id => b2.id).update_all({:home_popularity => 1, :popularity => 3})
      get :index, params: {:sort => "home_popularity"}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(2)
      expect(json['board'][0]['id']).to eq(b.global_id)
      expect(json['board'][1]['id']).to eq(b2.global_id)

      get :index, params: {:sort => "popularity"}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(2)
      expect(json['board'][0]['id']).to eq(b2.global_id)
      expect(json['board'][1]['id']).to eq(b.global_id)
    end
    
    it "should allow filtering by board category" do  
      u = User.create(:settings => {:public => true})
      b = Board.create(:user => u, :public => true, :settings => {'categories' => ['friends', 'ice_cream', 'cheese']})
      Board.where(:id => b.id).update_all({:home_popularity => 3, :popularity => 1})
      b2 = Board.create(:user => u, :public => true, :settings => {'categories' => ['ice_cream']})
      Board.where(:id => b2.id).update_all({:home_popularity => 1, :popularity => 3})
      b3 = Board.create(:user => u, :public => true, :settings => {'categories' => ['cheese']})
      Board.where(:id => b2.id).update_all({:home_popularity => 1, :popularity => 3})
      get :index, params: {:category => "ice_cream"}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(2)
      expect(json['board'][0]['id']).to eq(b2.global_id)
      expect(json['board'][1]['id']).to eq(b.global_id)
    end
    
    it "should allow sorting by custom_order" do
      u = User.create(:settings => {:public => true})
      b = Board.create(:user => u, :public => true, :settings => {'custom_order' => 2})
      Board.where(:id => b.id).update_all({:home_popularity => 3, :popularity => 1})
      b2 = Board.create(:user => u, :public => true, :settings => {'custom_order' => 1})
      Board.where(:id => b2.id).update_all({:home_popularity => 1, :popularity => 3})
      get :index, params: {:sort => "custom_order"}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(2)
      expect(json['board'][0]['id']).to eq(b2.global_id)
      expect(json['board'][1]['id']).to eq(b.global_id)
    end
    
    it "should only show boards with some home_popularity score when sorting by that" do
      u = User.create(:settings => {:public => true})
      b = Board.create(:user => u, :public => true)
      Board.where(:id => b.id).update_all({:home_popularity => 3})
      b2 = Board.create(:user => u, :public => true)
      get :index, params: {:sort => "home_popularity"}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(1)
      expect(json['board'][0]['id']).to eq(b.global_id)
    end
    
    it "should include shared boards if the user has any in user-search results" do
      token_user
      u2 = User.create
      b = Board.create(:user => u2, :settings => {'name' => 'cool board'}, :public => true)
      b.share_with(@user)
      get :index, params: {:user_id => @user.global_id, :q => 'cool', :include_shared => true}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(1)
      expect(json['board'][0]['id']).to eq(b.global_id)
    end
    
    it "should include boards downstream of shared boards in user-search results if enabled" do
      token_user
      u2 = User.create
      b = Board.create(:user => u2, :settings => {'name' => 'cool board'}, :public => true)
      b.share_with(@user, true)
      b2 = Board.create(:user => u2, :settings => {'name' => 'awesome board'}, :public => true)
      b.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b2.global_id, 'key' => b2.key}}
      ]
      b.save
      b3 = Board.create(:user => u2, :settings => {'name' => 'bodacious board'}, :public => true)
      b2.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
      ]
      b2.save
      Worker.process_queues
      
      get :index, params: {:user_id => @user.global_id, :q => 'bodacious', :include_shared => true}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(1)
      expect(json['board'][0]['id']).to eq(b3.global_id)

      get :index, params: {:user_id => @user.global_id, :q => 'board', :include_shared => true}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(3)
      expect(json['board'].map{|b| b['id'] }.sort).to eq([b.global_id, b2.global_id, b3.global_id])
    end
    
    it "should not include boards downstream of shared boards in user-search results if by a different author" do
      token_user
      u2 = User.create
      u3 = User.create
      b = Board.create(:user => u2, :settings => {'name' => 'cool board'}, :public => true)
      b.share_with(@user, true)
      b2 = Board.create(:user => u3, :settings => {'name' => 'awesome board'}, :public => true)
      b.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b2.global_id, 'key' => b2.key}}
      ]
      b.save
      b3 = Board.create(:user => u2, :settings => {'name' => 'bodacious board'}, :public => true)
      b2.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
      ]
      b2.save
      Worker.process_queues
      
      get :index, params: {:user_id => @user.global_id, :q => 'awesome', :include_shared => true}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(0)

      get :index, params: {:user_id => @user.global_id, :q => 'board', :include_shared => true}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(2)
      expect(json['board'][0]['id']).to eq(b.global_id)
      expect(json['board'][1]['id']).to eq(b3.global_id)
    end
  end

  describe "show" do
    it "should not require api token" do
      u = User.create
      b = Board.create(:user => u, :public => true)
      get :show, params: {:id => b.global_id}
      expect(response).to be_success
    end
    
    it "should require existing object" do
      u = User.create
      b = Board.create(:user => u)
      get :show, params: {:id => '1_19999'}
      assert_not_found
    end

    it "should require authorization" do
      u = User.create
      b = Board.create(:user => u)
      get :show, params: {:id => b.global_id}
      assert_unauthorized
    end
    
    it "should return a json response" do
      token_user
      b = Board.create(:user => @user)
      get :show, params: {:id => b.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['id']).to eq(b.global_id)
    end
    
    it "should return deleted status if the information is allowed" do
      token_user
      b = Board.create(:user => @user)
      key = b.key
      b.destroy
      Worker.process_queues
      get :show, params: {:id => key}
      assert_not_found(key)
      json = JSON.parse(response.body)
      expect(json['deleted']).to eq(true)
    end
    
    it "should not return deleted status for non-existent boards" do
      token_user
      Worker.process_queues
      get :show, params: {:id => "#{@user.user_name}/not-a-board"}
      assert_not_found("#{@user.user_name}/not-a-board")
      json = JSON.parse(response.body)
      expect(json['deleted']).to eq(nil)
    end

    it "should return deleted status if the information is allowed when searching by id" do
      token_user
      b = Board.create(:user => @user)
      key = b.global_id
      b.destroy
      Worker.process_queues
      get :show, params: {:id => key}
      assert_not_found(key)
      json = JSON.parse(response.body)
      expect(json['deleted']).to eq(true)
    end
    
    it "should not return deleted status if not allowed" do
      token_user
      u = User.create
      b = Board.create(:user => u, :public => true)
      key = b.key
      b.destroy
      Worker.process_queues
      get :show, params: {:id => key}
      assert_not_found
      json = JSON.parse(response.body)
      expect(json['deleted']).to eq(nil)
    end
    
    it "should return never_existed status if allowed" do
      token_user
      u = User.create
      User.link_supervisor_to_user(@user, u)
      get :show, params: {:id => "#{u.user_name}/bacon"}
      assert_not_found("#{u.user_name}/bacon")
      json = JSON.parse(response.body)
      expect(json['deleted']).to eq(nil)
      expect(json['never_existed']).to eq(true)
    end
    
    it "should not return never_existed status if not allowed" do
      token_user
      u = User.create
      get :show, params: {:id => "#{u.user_name}/bacon"}
      assert_not_found
      json = JSON.parse(response.body)
      expect(json['deleted']).to eq(nil)
      expect(json['never_existed']).to eq(nil)
    end
  end
  
  describe "create" do
    it "should require api token" do
      post :create
      assert_missing_token
    end
    
    it "should create a new board" do
      token_user
      post :create, params: {:board => {:name => "my board"}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['name']).to eq('my board')
    end
    
    it "should error gracefully on board creation fail" do
      expect_any_instance_of(Board).to receive(:process_params){|u| u.add_processing_error("bacon") }.and_return(false)
      token_user
      post :create, params: {:board => {:name => "my board"}}
      json = JSON.parse(response.body)
      expect(json['error']).to eq("board creation failed")
      expect(json['errors']).to eq(["bacon"])
    end
    
    it "should allow creating a board for a supervisee" do
      token_user
      com = User.create
      User.link_supervisor_to_user(@user, com, nil, true)
      post :create, params: {:board => {:name => "my board", :for_user_id => com.global_id}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['name']).to eq('my board')
      expect(json['board']['user_name']).to eq(com.user_name)
    end
    
    it "should allow links if the author can access the links but not the supervisee" do
      token_user
      u = User.create
      User.link_supervisor_to_user(@user, u, nil, true)
      b = Board.create(:user => @user)
      post :create, params: {:board => {:name => "copy", :for_user_id => u.global_id, :buttons => [{'id' => '1', 'load_board' => {'id' => b.global_id}, 'label' => 'farce'}]}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['id']).to_not eq(nil)
      Worker.process_queues
      b2 = Board.find_by_path(json['board']['id'])
      expect(b2).to_not eq(b)
      expect(b2.settings['downstream_board_ids']).to eq([b.global_id])
    end

    it "should allow links if the supervisee can access the links but not the author" do
      token_user
      u = User.create
      User.link_supervisor_to_user(@user, u, nil, true)
      b = Board.create(:user => u)
      post :create, params: {:board => {:name => "copy", :for_user_id => u.global_id, :buttons => [{'id' => '1', 'load_board' => {'id' => b.global_id}, 'label' => 'farce'}]}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['id']).to_not eq(nil)
      Worker.process_queues
      b2 = Board.find_by_path(json['board']['id'])
      expect(b2).to_not eq(b)
      expect(b2.settings['downstream_board_ids']).to eq([b.global_id])
    end
    
    it "should not allow links if the supervisee can access the links but not the author" do
      token_user
      u = User.create
      u2 = User.create
      User.link_supervisor_to_user(@user, u, nil, true)
      b = Board.create(:user => u2)
      post :create, params: {:board => {:name => "copy", :for_user_id => u.global_id, :buttons => [{'id' => '1', 'load_board' => {'id' => b.global_id}, 'label' => 'farce'}]}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['id']).to_not eq(nil)
      Worker.process_queues
      b2 = Board.find_by_path(json['board']['id'])
      expect(b2).to_not eq(b)
      expect(b2.settings['downstream_board_ids']).to eq([])
    end
    
    it "should not allow creating a board for a random someone else" do
      token_user
      com = User.create
      post :create, params: {:board => {:name => "my board", :for_user_id => com.global_id}}
      assert_unauthorized
    end
    
    it "should not allow creating a board for a supervisee if you don't have edit privileges" do
      token_user
      com = User.create
      User.link_supervisor_to_user(@user, com, nil, false)
      post :create, params: {:board => {:name => "my board", :for_user_id => com.global_id}}
      assert_unauthorized
    end

    it "should preserve grid order" do
      token_user
      request.headers['Content-Type'] = 'application/json'
      post :create, params: {}, body: 
      {
        :board => {
          :name => "cool board 2",
          :buttons => [{'id' => '1', 'label' => 'can'}, {'id' => '2', 'label' => 'span'}],
          :grid => {
            'rows' => 1, 'columns' => 3,
            'order' => [[1, nil, 2]]
          }
        }
      }.to_json
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['name']).to eq("cool board 2")
      expect(json['board']['grid']['order']).to eq([[1, nil, 2]])
    end
  end
  
  describe "update" do
    it "should require api token" do
      put :update, params: {:id => "1_1"}
      assert_missing_token
    end
    
    it "should error on not found" do
      u = User.create
      token_user
      put :update, params: {:id => "1_19999"}
      assert_not_found
    end

    it "should require edit permissions" do
      u = User.create
      b = Board.create(:user => u)
      token_user
      put :update, params: {:id => b.global_id}
      assert_unauthorized
    end
    
    it "should update the board" do
      token_user
      b = Board.create(:user => @user)
      put :update, params: {:id => b.global_id, :board => {:name => "cool board 2"}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['name']).to eq("cool board 2")
    end
    
    it "should allow linking to private boards with access permission" do
      token_user
      b = Board.create(:user => @user)
      b2 = Board.create(:user => @user)
      button = {:id => 123, :load_board => {:id => b2.global_id, :key => b2.key}}
      put :update, params: {:id => b.global_id, :board => {:name => "cool board 2", :buttons => [button]}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['name']).to eq("cool board 2")
      expect(json['board']['buttons'].length).to eq(1)
      expect(json['board']['buttons'][0]['load_board']).to eq({'id' => b2.global_id, 'key' => b2.key})
    end
    
    it "should now allow linking to private boards without access permission" do
      token_user
      @u2 = User.create
      b = Board.create(:user => @user)
      b2 = Board.create(:user => @u2)
      button = {:id => 123, :load_board => {:id => b2.global_id, :key => b2.key}}
      put :update, params: {:id => b.global_id, :board => {:name => "cool board 2", :buttons => [button]}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['name']).to eq("cool board 2")
      expect(json['board']['buttons'].length).to eq(1)
      expect(json['board']['buttons'][0]['load_board']).to eq(nil)
    end
    
    it "should error gracefully on board update fail" do
      expect_any_instance_of(Board).to receive(:process_params){|u| u.add_processing_error("bacon") }.and_return(false)
      token_user
      b = Board.create(:user => @user)
      put :update, params: {:id => b.global_id, :board => {:name => "cool board 2"}}
      json = JSON.parse(response.body)
      expect(json['error']).to eq("board update failed")
      expect(json['errors']).to eq(["bacon"])
    end
    
    it "should properly share with a second user" do
      token_user
      u2 = User.create
      u3 = User.create
      b = Board.create(:user => @user)
      b.share_with(u2)
      b = Board.find(b.id)
      @user = User.find(@user.id)
      
      put :update, params: {:id => b.global_id, :board => {:sharing_key => "add_shallow-#{@user.user_name}"}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['shared_users'].length).to eq(2)
      
      b = Board.find(b.id)
      expect(b.shared_users.length).to eq(2)
    end
    
    it "should preserve grid order" do
      token_user
      b = Board.create(:user => @user)
      request.headers['Content-Type'] = 'application/json'
      put :update, params: {:id => b.global_id}, body: 
      {
        :board => {
          :name => "cool board 2",
          :buttons => [{'id' => '1', 'label' => 'can'}, {'id' => '2', 'label' => 'span'}],
          :grid => {
            'rows' => 1, 'columns' => 3,
            'order' => [[1, nil, 2]]
          }
        }
      }.to_json
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['name']).to eq("cool board 2")
      expect(json['board']['grid']['order']).to eq([[1, nil, 2]])
    end
    
    it "should support single-button updating" do
      token_user
      b = Board.create(:user => @user)
      b.settings['buttons'] = [
        {'id' => '1', 'label' => 'fred'}, {'id' => '2', 'label' => 'drop dead'}
      ]
      b.save
      put :update, params: {:id => b.global_id, 'button' => {
        'id' => '2',
        'sound_id' => '12345'
      }}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['buttons'][1]).to eq({'id' => '2', 'label' => 'drop dead', 'sound_id' => '12345'})
    end
  end
  
  describe "star" do
    it "should require api token" do
      post :star, params: {:board_id => "1_1"}
      assert_missing_token
    end
    
    it "should error on not found" do
      token_user
      post :star, params: {:board_id => "1_1"}
      assert_not_found
    end
    
    it "should star the board and return a json response" do
      token_user
      b = Board.create(:user => @user)
      post :star, params: {:board_id => b.global_id}
      expect(response).to be_success
      expect(b.reload.settings['starred_user_ids']).to eq([@user.global_id])
      json = JSON.parse(response.body)
      expect(json).to eq({'starred' => true, 'stars' => 1})
    end
  end
  
  describe "unstar" do
    it "should require api token" do
      delete :star, params: {:board_id => "1_1"}
      assert_missing_token
    end

    it "should error on not found" do
      token_user
      delete :star, params: {:board_id => "1_1"}
      assert_not_found
    end

    it "should star the board and return a json response" do
      token_user
      b = Board.create(:user => @user, :settings => {'starred_user_ids' => [@user.global_id]})
      delete :unstar, params: {:board_id => b.global_id}
      expect(response).to be_success
      expect(b.reload.settings['starred_user_ids']).to eq([])
      json = JSON.parse(response.body)
      expect(json).to eq({'starred' => false, 'stars' => 0})
    end
  end
  
  describe "destroy" do
    it "should require api token" do
      delete :destroy, params: {:id => "1_1"}
      assert_missing_token
    end

    it "should error on not found" do
      token_user
      delete :destroy, params: {:id => "1_1"}
      assert_not_found
    end
    
    it "should require permission" do
      u = User.create
      b = Board.create(:user => u)
      token_user
      delete :destroy, params: {:id => b.global_id}
      assert_unauthorized
    end
    
    it "should delete the board and return a json response" do
      token_user
      b = Board.create(:user => @user)
      delete :destroy, params: {:id => b.global_id}
      expect(response).to be_success
      expect(Board.find_by(:id => b.id)).to eq(nil)
      json = JSON.parse(response.body)
      expect(json['board']['id']).to eq(b.global_id)
    end
  end
  
  describe "stats" do
    it "should require api token" do
      get :stats, params: {:board_id => '1_1'}
      assert_missing_token
    end
    
    it "should require permission" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      get :stats, params: {:board_id => b.global_id}
      assert_unauthorized
    end
    
    it "should return basic stats" do
      token_user
      b = Board.new(:user => @user)
      expect(b).to receive(:generate_stats).and_return(nil)
      b.settings = {}
      b.settings['stars'] = 4
      b.settings['uses'] = 3
      b.settings['home_uses'] = 4
      b.settings['forks'] = 1
      b.save
      
      get :stats, params: {:board_id => b.global_id}
      expect(response).to be_success
      hash = JSON.parse(response.body)
      expect(hash['uses']).to eq(3)
    end
  end
  
  describe "download" do
    it "should not error on not found" do
      post :download, params: {:board_id => "1_19999"}
      assert_not_found
    end

    it "should not require api token" do
      u = User.create
      b = Board.create(:user => u, :public => true)
      post :download, params: {:board_id => b.global_id}
      expect(response).to be_success
    end
    
    it "should require permission" do
      u = User.create
      b = Board.create(:user => u)
      post :download, params: {:board_id => b.global_id}
      assert_unauthorized
    end
    
    it "should allow unauthenticated user to download if public"
    
    it "should return a progress record" do
      u = User.create
      b = Board.create(:user => u, :public => true)
      post :download, params: {:board_id => b.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['progress']['id']).not_to eq(nil)
    end

    it "should schedule the correct parameters" do
      u = User.create
      b = Board.create(:user => u, :public => true)
      post :download, params: {:board_id => b.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['progress']['id']).not_to eq(nil)
      progress = Progress.find_by_global_id(json['progress']['id'])
      expect(progress.settings['class']).to eq('Board')
      expect(progress.settings['id']).to eq(b.id)
      expect(progress.settings['method']).to eq('generate_download')
      expect(progress.settings['arguments']).to eq([nil, nil, {
        'include' => nil, 
        'headerless' => false, 
        'text_on_top' => false, 
        'transparent_background' => false,
        'text_only' => false,
        'text_case' => nil,
        'font' => nil
      }])

      token_user
      post :download, params: {:board_id => b.global_id, 'type' => 'bacon', 'include' => 'something', 'headerless' => '1', 'text_on_top' => '0', 'transparent_background' => '1', 'text_only' => '1', 'text_case' => 'lower', 'font' => 'cheddar'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['progress']['id']).not_to eq(nil)
      progress = Progress.find_by_global_id(json['progress']['id'])
      expect(progress.settings['class']).to eq('Board')
      expect(progress.settings['id']).to eq(b.id)
      expect(progress.settings['method']).to eq('generate_download')
      expect(progress.settings['arguments']).to eq([@user.global_id, 'bacon', {
        'include' => 'something', 
        'headerless' => true, 
        'text_on_top' => false, 
        'transparent_background' => true,
        'text_only' => true,
        'text_case' => 'lower',
        'font' => 'cheddar'
      }])
    end
  end

  
  describe "rename" do
    it "should require api token" do
      post :rename, params: {:board_id => "1_1"}
      assert_missing_token
    end
    
    it "should error on not found" do
      token_user
      post :rename, params: {:board_id => "1_19999"}
      assert_not_found
    end

    it "should require edit permissions" do
      u = User.create
      b = Board.create(:user => u)
      token_user
      post :rename, params: {:board_id => b.global_id}
      assert_unauthorized
    end
    
    it "should rename the board" do
      token_user
      b = Board.create(:user => @user)
      post :rename, params: {:board_id => b.global_id, :old_key => b.key, :new_key => "#{@user.user_name}/bacon"}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq({'rename' => true, 'key' => "#{@user.user_name}/bacon"})
    end

    it "should require the correct old_key" do
      token_user
      b = Board.create(:user => @user)
      post :rename, params: {:board_id => b.global_id, :old_key => b.key + "asdf", :new_key => "#{@user.user_name}/bacon"}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json).not_to eq(nil)
      expect(json['error']).to eq('board rename failed')
    end
    
    it "should require a valid new_key" do
      token_user
      b = Board.create(:user => @user)
      post :rename, params: {:board_id => b.global_id, :old_key => b.key}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json).not_to eq(nil)
      expect(json['error']).to eq('board rename failed')
    end
    
    it "should report if there was a new_key name collision" do
      token_user
      b = Board.create(:user => @user)
      b2 = Board.create(:user => @user)
      post :rename, params: {:board_id => b.global_id, :old_key => b.key, :new_key => b2.key}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json).not_to eq(nil)
      expect(json['error']).to eq('board rename failed')
      expect(json['collision']).to eq(true)
    end
    
    it "should not allow changing the username prefix for the new_key" do
      token_user
      b = Board.create(:user => @user)
      post :rename, params: {:board_id => b.global_id, :old_key => b.key, :new_key => "#{@user.user_name}x/bacon"}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json).not_to eq(nil)
      expect(json['error']).to eq('board rename failed')
    end
  end
  
  describe "import" do
    it "should require api token" do
      post :import, params: {:url => 'http://www.example.com/file.obf'}
      assert_missing_token
    end
    
    it "should schedule processing for url" do
      token_user
      p = Progress.create
      expect(Progress).to receive(:schedule).with(Board, :import, @user.global_id, 'http://www.example.com/file.obf').and_return(p)
      post :import, params: {:url => 'http://www.example.com/file.obf'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['progress']['id']).to eq(p.global_id)
    end
    
    it "should return import upload parameters for no url" do
      token_user
      post :import, params: {:type => 'obf'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['remote_upload']).to_not eq(nil)
      expect(json['remote_upload']['upload_url']).to_not eq(nil)
    end
  end
  
  describe "unlink" do
    it "should require api token" do
      post :unlink
      assert_missing_token
    end
    
    it "should require a valid board" do
      token_user
      post :unlink, params: {:board_id => 'asdf'}
      assert_not_found
    end
    
    it "should require user edit permission" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      post :unlink, params: {:board_id => b.global_id, :user_id => u.global_id}
      assert_unauthorized
    end
    
    it "should require delete permission to delete a board" do
      token_user
      u = User.create
      u2 = User.create
      b = Board.create(:user => u2)
      User.link_supervisor_to_user(@user, u, nil, true)
      post :unlink, params: {:board_id => b.global_id, :user_id => u.global_id, :type => 'delete'}
      assert_unauthorized
    end
    
    it "should delete a board if allowed" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      User.link_supervisor_to_user(@user, u, nil, true)
      post :unlink, params: {:board_id => b.global_id, :user_id => u.global_id, :type => 'delete'}
      expect(response).to be_success
    end
    
    it "should unstar a board for the specified user" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      b.star!(u, true)
      expect(b.starred_by?(u)).to eq(true)
      User.link_supervisor_to_user(@user, u, nil, true)
      post :unlink, params: {:board_id => b.global_id, :user_id => u.global_id, :type => 'unstar'}
      expect(response).to be_success
      expect(b.reload.starred_by?(u)).to eq(false)
    end
    
    it "should error on an unrecognized action" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      b.star!(u, true)
      User.link_supervisor_to_user(@user, u, nil, true)
      post :unlink, params: {:board_id => b.global_id, :user_id => u.global_id, :type => 'bacon'}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['error']).to eq('unrecognized type')
    end
    
    it "should unlink a shared board for the specified user" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      b.share_with(@user)
      expect(b.shared_with?(@user)).to eq(true)
      post :unlink, params: {:board_id => b.global_id, :user_id => @user.global_id, :type => 'unlink'}
      expect(response).to be_success
      expect(b.reload.shared_with?(@user.reload)).to eq(false)
    end
  end
  
  describe "history" do
    it "should require an access token" do
      get :history, params: {:board_id => "asdf/asdf"}
      assert_missing_token
    end
    
    it "should require a valid board" do
      token_user
      get :history, params: {:board_id => "asdf/asdf"}
      assert_not_found
    end
    
    it "should require permission" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      get :history, params: {:board_id => b.key}
      assert_unauthorized
    end
    
    with_versioning do
      it "should return a list of versions" do
        token_user
        PaperTrail.whodunnit = "user:#{@user.global_id}"
        b = Board.create(:user => @user, :settings => {'buttons' => []})
        get :history, params: {:board_id => b.key}
        expect(response).to be_success
        json = JSON.parse(response.body)
        expect(json['boardversion']).not_to eq(nil)
        expect(json['boardversion'].length).to eq(1)
        expect(json['boardversion'][0]['action']).to eq('created')
        expect(json['boardversion'][0]['modifier']['user_name']).to eq(@user.user_name)
      end
    
      it "should return a list of versions for a deleted board" do
        token_user
        PaperTrail.whodunnit = "user:#{@user.global_id}"
        b = Board.create(:user => @user, :settings => {'buttons' => []})
        key = b.key

        vs = b.versions.where('whodunnit IS NOT NULL')
        expect(vs.length).to eq(1)
        vs.update_all(:created_at => 5.seconds.ago)
        
        b.destroy

        vs = b.versions.where('whodunnit IS NOT NULL')
        expect(vs.length).to eq(2)
        
        get :history, params: {:board_id => key}
        expect(response).to be_success
        json = JSON.parse(response.body)
        expect(json['boardversion']).not_to eq(nil)
        expect(json['boardversion'].length).to eq(2)
        expect(json['boardversion'][0]['action']).to eq('deleted')
        expect(json['boardversion'][1]['action']).to eq('created')
        expect(json['boardversion'][1]['modifier']['user_name']).to eq(@user.user_name)
      end
      
      it "should include board copy as a version" do
        token_user
        PaperTrail.whodunnit = "user:#{@user.global_id}"
        u = User.create
        b = Board.create(:user => u, :public => true)
        b2 = Board.create(:user => u, :public => true)
        b.settings['buttons'] = [{'id' => 1, 'load_board' => {'id' => b2.global_id}}]
        b.instance_variable_set('@buttons_changed', true)
        b.save
        Worker.process_queues
        new_b = b.copy_for(@user)
        Worker.process_queues
        
        @user.copy_board_links(b.global_id, new_b.global_id, [], "user:#{@user.global_id}")
        Worker.process_queues
        
        new_b.reload
        expect(new_b.settings['downstream_board_ids'].length).to eq(1)
        expect(new_b.settings['downstream_board_ids'][0]).to_not eq(b2.global_id)
        new_b2 = Board.find_by_global_id(new_b.settings['downstream_board_ids'][0])
        expect(new_b2).to_not eq(nil)
        expect(new_b2.parent_board_id).to eq(b2.id)
        
        vs = Board.user_versions(new_b.global_id)
        expect(vs.length).to eq(2)
        vs2 = Board.user_versions(new_b2.global_id)
        expect(vs2.length).to eq(1)
        
        get :history, params: {:board_id => new_b2.key}
        expect(response).to be_success
        json = JSON.parse(response.body)
        expect(json['boardversion']).not_to eq(nil)
        expect(json['boardversion'].length).to eq(1)
        expect(json['boardversion'][0]['action']).to eq('created')
        expect(json['boardversion'][0]['modifier']).not_to eq(nil)
        expect(json['boardversion'][0]['modifier']['user_name']).to eq(@user.user_name)
        
        new_b2.save!
        vs2 = Board.user_versions(new_b2.global_id)
        expect(vs2.length).to eq(2)
        get :history, params: {:board_id => new_b2.key}
        expect(response).to be_success
        json = JSON.parse(response.body)
        expect(json['boardversion']).not_to eq(nil)
        expect(json['boardversion'].length).to eq(2)
        expect(json['boardversion'][0]['action']).to eq('updated')
        expect(json['boardversion'][0]['modifier']).not_to eq(nil)
        expect(json['boardversion'][0]['modifier']['user_name']).to eq(@user.user_name)
        expect(json['boardversion'][1]['action']).to eq('copied')
        expect(json['boardversion'][1]['modifier']).not_to eq(nil)
        expect(json['boardversion'][1]['modifier']['user_name']).to eq(@user.user_name)
      end
    
      it "should not return a list of versions for a deleted board if not allowed" do
        token_user
        u = User.create
        b = Board.create(:user => u, :settings => {'buttons' => []}, :public => true)
        key = b.key
        b.destroy
        get :history, params: {:board_id => key}
        assert_unauthorized
      end
    end
  end
  
  describe "share_response" do
    it "should require api token" do
      post :share_response, params: {:board_id => "asdf/asdf"}
      assert_missing_token
    end
    
    it "should require a valid board" do
      token_user
      post :share_response, params: {:board_id => "asdf/asdf"}
      assert_not_found
    end
    
    it "should require view permission" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      post :share_response, params: {:board_id => b.key}
      assert_unauthorized
    end
    
    it "should approve if specified" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      b.share_with(@user, true, true)
      post :share_response, params: {:board_id => b.key, :approve => 'true'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['approved']).to eq(true)
      expect(json['updated']).to eq(true)
    end
    
    it "should reject if specified" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      b.share_with(@user, true, true)
      post :share_response, params: {:board_id => b.key, :approve => 'false'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['approved']).to eq(false)
      expect(json['updated']).to eq(true)
    end
    
    it "should error if unexpected response" do
      token_user
      u = User.create
      b = Board.create(:user => u, :public => true)
      post :share_response, params: {:board_id => b.key, :approve => 'true'}
      assert_error('board share update failed', 400)
    end
  end
  
  describe "copies" do
    it "should require api token" do
      get :copies, params: {:board_id => "asdf/asdf"}
      assert_missing_token
    end
    
    it "should require a valid board" do
      token_user
      get :copies, params: {:board_id => "asdf/asdf"}
      assert_not_found
    end
    
    it "should require view permission" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      get :copies, params: {:board_id => b.key}
      assert_unauthorized
    end
    
    it "should return a list of copies for the user" do
      token_user
      b = Board.create(:user => @user)
      b2 = b.copy_for(@user)
      get :copies, params: {:board_id => b.key}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board'].length).to eq(1)
    end
  end
  
  describe "translate" do
    it "should require api token" do
      post 'translate', params: {:board_id => '1_1234'}
      assert_missing_token
    end
    
    it "should require a valid board" do
      token_user
      post 'translate', params: {:board_id => '1_1234'}
      assert_not_found('1_1234')
    end
    
    it "should require permission" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      post 'translate', params: {:board_id => b.global_id}
      assert_unauthorized
    end
    
    it "should schedule a translation" do
      token_user
      b = Board.create(:user => @user)
      post 'translate', params: {:board_id => b.global_id, 'translations' => {}, 'source_lang' => 'en', 'destination_lang' => 'es', 'board_ids_to_translate' => []}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['progress']).to_not eq(nil)
      progress = Progress.find_by_global_id(json['progress']['id'])
      expect(Worker.scheduled_for?('priority', Progress, :perform_action, progress.id)).to eq(true)
      expect(progress.settings['method']).to eq('translate_set')
    end
  end
  
  describe "swap_images" do
    it "should require api token" do
      post 'swap_images', params: {:board_id => '1_1234'}
      assert_missing_token
    end
    
    it "should require a valid board" do
      token_user
      post 'swap_images', params: {:board_id => '1_1234'}
      assert_not_found('1_1234')
    end
    
    it "should require permission" do
      token_user
      u = User.create
      b = Board.create(:user => u)
      post 'swap_images', params: {:board_id => b.global_id}
      assert_unauthorized
    end
    
    it "should schedule a swap" do
      token_user
      b = Board.create(:user => @user)
      post 'swap_images', params: {:board_id => b.global_id, 'library' => 'asdf', 'board_ids_to_translate' => []}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['progress']).to_not eq(nil)
      progress = Progress.find_by_global_id(json['progress']['id'])
      expect(Worker.scheduled_for?('priority', Progress, :perform_action, progress.id)).to eq(true)
      expect(progress.settings['method']).to eq('swap_images')
    end
  end
  
  describe "protected image use" do
    it "should correctly mark a board as protected" do
      token_user
      post :create, params: {"board":
        {"name": "lptest","key": nil,"description": nil,"created": nil,"updated": nil,"user_name": nil,"locale": "en_US","full_set_revision": nil,"current_revision": nil,"for_user_id": "self","parent_board_id": nil,"parent_board_key": nil,"link": nil,"image_url": nil,"grid": {"rows": 2,"columns": 4},"license": {"type": "private"},"copies": nil,"word_suggestions": false,"public": true,"brand_new": false,"protected": false,"non_author_uses": nil,"downstream_boards": nil,"immediately_upstream_boards": nil,"unlinked_buttons": nil,"forks": nil,"total_buttons": nil,"sharing_key": nil,"starred": false,"stars": nil,"non_author_starred": false,"retrieved": nil,"images": []}
      }
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['name']).to eq('lptest')
      expect(json['board']['public']).to eq(true)
      b = Board.find_by_path(json['board']['id'])
      expect(b).to_not eq(nil)
      Worker.process_queues

      bi1 = ButtonImage.process_new({"url": "http://localhost:3000/api/v1/users/1_1/protected_image/lessonpix/30983","content_type": nil,"width": nil,"height": nil,"pending": false,"avatar": false,"badge": false,"protected": true,"suggestion": "cat","external_id": nil,"search_term": nil,"license": {"type": "private","source_url": "http://lessonpix.com/pictures/30983/cat","author_name": "LessonPix","author_url": "http://lessonpix.com","uneditable": true},"file": false,"retrieved": nil}, {:user => @user, :remote_upload_possible => true})
      expect(bi1.protected?).to eq(true)
      bi2 = ButtonImage.create(:settings => {'protected' => true})
      bi3 = ButtonImage.create(:settings => {'protected' => false})
      Worker.process_queues
      put :update, params: {:id => b.global_id, "board":{"name": "lptest","key": "example/lptest_2","description": nil,"created": "2017-02-24T20:12:01.000Z","updated": "2017-02-24T20:12:01.000Z","user_name": "example","locale": "en_US","full_set_revision": "0b5d2fa3a4f31f42301f34fa6e288f97","current_revision": "0b5d2fa3a4f31f42301f34fa6e288f97","for_user_id": "self","parent_board_id": nil,"parent_board_key": nil,"link": "http://localhost:3000/example/lptest_2","image_url": "https://s3.amazonaws.com/opensymbols/libraries/arasaac/board_3.png","buttons": [{"label": "cat","image_id": bi1.global_id,"background_color": "rgb(255, 204, 170)","border_color": "rgb(255, 112, 17)","hidden": false,"link_disabled": false,"add_to_vocalization": false,"home_lock": false,"blocking_speech": false,"part_of_speech": "noun","suggested_part_of_speech": "noun","id": 1,"dark_border_color": "rgb(246, 98, 0)","dark_background_color": "rgb(255, 189, 144)","text_color": "rgb(0, 0, 0)"}],"grid": {"rows": 2,"columns": 4,"order": [[1,nil,nil,nil],[nil,nil,nil,nil]]},"license": {"type": "private"},"permissions": {"user_id": "1_1","view": true,"edit": true,"delete": true,"share": true},"copies": 0,"word_suggestions": false,"public": true,"brand_new": false,"protected": false,"non_author_uses": 0,"downstream_boards": 0,"immediately_upstream_boards": 0,"unlinked_buttons": 0,"forks": 0,"total_buttons": 0,"shared_users": [],"sharing_key": nil,"starred": false,"stars": 0,"non_author_starred": false,"retrieved": 1487967122808,"images": []}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['protected']).to eq(true)
      expect(json['board']['public']).to eq(false)

      put :update, params: {:id => b.global_id, :board => {
        'public' => true,
        'buttons' => [
          {'id' => 1, 'image_id' => bi1.global_id, 'label' => 'a'},
          {'id' => 2, 'image_id' => bi2.global_id, 'label' => 'b'}
        ],
        'grid' => {
          rows: 2,
          columns: 4,
          order: [
            [1, 2, nil, nil],
            [nil, nil, nil, nil]
          ]
        }
      }}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['protected']).to eq(true)
      expect(json['board']['public']).to eq(false)

      put :update, params: {:id => b.global_id, :board => {
        'public' => true,
        'buttons' => [
          {'id' => 1, 'image_id' => bi3.global_id, 'label' => 'a'}
        ],
        'grid' => {
          rows: 2,
          columns: 4,
          order: [
            [1, nil, nil, nil],
            [nil, nil, nil, nil]
          ]
        }
      }}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['board']['protected']).to eq(false)
      expect(json['board']['public']).to eq(false)
    end
  end
end
