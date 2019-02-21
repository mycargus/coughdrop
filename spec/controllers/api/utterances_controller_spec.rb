require 'spec_helper'

describe Api::UtterancesController, :type => :controller do
  describe "POST create" do
    it "should require api token" do
      post :create, params: {:utterance => {}}
      assert_missing_token
    end
    
    it "should generate a valid utterance" do
      token_user
      post :create, params: {:utterance => {:button_list => [{label: "ok"}], :sentence => "ok"}}
      expect(response).to be_success
      u = Utterance.last
      expect(u).not_to eq(nil)
      expect(u.data['button_list']).to eq([{'label' => 'ok'}])
      expect(u.data['sentence']).to eq('ok')
    end
    
    it "should return a json response" do
      token_user
      post :create, params: {:utterance => {:button_list => [{label: "ok"}], :sentence => "ok"}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['utterance']['id']).not_to eq(nil)
      expect(json['utterance']['link']).not_to eq(nil)
      expect(json['utterance']['button_list']).not_to eq(nil)
      expect(json['utterance']['sentence']).not_to eq(nil)
      expect(json['utterance']['image_url']).not_to eq(nil)
    end
    
    it "should error gracefully on utterance create fail" do
      token_user
      expect_any_instance_of(Utterance).to receive(:process_params){|u| u.add_processing_error("bacon") }.and_return(false)
      post :create, params: {:utterance => {:button_list => [{label: "ok"}], :sentence => "ok"}}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['error']).to eq("utterance creation failed")
      expect(json['errors']).to eq(["bacon"])
    end
  end
  
  describe "PUT update" do
    it "should require api token" do
      put :update, params: {:id => '1234', :utterance => {}}
      assert_missing_token
    end
    
    it "should update an utterance" do
      token_user
      utterance = Utterance.create(:user => @user)
      put :update, params: {:id => utterance.global_id, :utterance => {:show_user => true, :image_url => "http://www.pic.com/pic.png"}}
      expect(response).to be_success
      u = Utterance.last.reload
      expect(u).not_to eq(nil)
      expect(u.data['show_user']).to eq(true)
      expect(u.data['image_url']).to eq("http://www.pic.com/pic.png")
    end
    
    it "should return a json response" do
      token_user
      utterance = Utterance.create(:user => @user)
      put :update, params: {:id => utterance.global_id, :utterance => {:show_user => true, :sentence => "ok"}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['utterance']['id']).not_to eq(nil)
      expect(json['utterance']['link']).not_to eq(nil)
      expect(json['utterance']['button_list']).to eq(nil)
      expect(json['utterance']['sentence']).to eq("ok")
      expect(json['utterance']['show_user']).to eq(true)
      expect(json['utterance']['permissions']).to eq({'view' => true, 'edit' => true, 'user_id' => @user.global_id})
      expect(json['utterance']['user']['id']).to eq(@user.global_id)
      expect(json['utterance']['user']['user_name']).to eq(@user.user_name)
      expect(json['utterance']['image_url']).not_to eq(nil)
    end

    it "should return a json response" do
      token_user
      utterance = Utterance.create(:user => @user)
      put :update, params: {:id => utterance.global_id, :utterance => {:show_user => false, :sentence => "ok"}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['utterance']['id']).not_to eq(nil)
      expect(json['utterance']['link']).not_to eq(nil)
      expect(json['utterance']['button_list']).to eq(nil)
      expect(json['utterance']['sentence']).to eq("ok")
      expect(json['utterance']['show_user']).to eq(false)
      expect(json['utterance']['permissions']).to eq({'view' => true, 'edit' => true, 'user_id' => @user.global_id})
      expect(json['utterance']['user']['id']).to eq(@user.global_id)
      expect(json['utterance']['user']['user_name']).to eq(@user.user_name)
      expect(json['utterance']['image_url']).not_to eq(nil)
    end
    
    it "should error gracefully on utterance create fail" do
      token_user
      utterance = Utterance.create(:user => @user)
      expect_any_instance_of(Utterance).to receive(:process_params){|u| u.add_processing_error("bacon") }.and_return(false)
      put :update, params: {:id => utterance.global_id, :utterance => {:button_list => [{label: "ok"}], :sentence => "ok"}}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['error']).to eq("utterance update failed")
      expect(json['errors']).to eq(["bacon"])
    end
  end
  
  describe "POST share" do
    it "should require api token" do
      post :share, params: {:utterance_id => 'asdf'}
      assert_missing_token
    end
    
    it "should error if not found" do
      token_user
      post :share, params: {:utterance_id => 'asdf'}
      assert_not_found
    end
    
    it "should require edit permission" do
      token_user
      u = User.create
      utterance = Utterance.create(:user => u)
      post :share, params: {:utterance_id => utterance.global_id}
      assert_unauthorized
    end
    
    it "should return success on success" do
      token_user
      utterance = Utterance.create(:user => @user)
      post :share, params: {:utterance_id => utterance.global_id, :email => 'bob@example.com'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['shared']).to eq(true)
    end

    it "should require an existing sharer if specified" do
      token_user
      utterance = Utterance.create(:user => @user)
      post :share, params: {:utterance_id => utterance.global_id, :email => 'bob@example.com', :sharer_id => 'asdf'}
      assert_not_found('asdf')
    end

    it "should require supervisor permission to specify a sharer" do
      token_user
      u = User.create
      User.link_supervisor_to_user(u, @user)
      utterance = Utterance.create(:user => @user)
      post :share, params: {:utterance_id => utterance.global_id, :email => 'bob@example.com', :sharer_id => u.global_id}
      assert_unauthorized
    end

    it "should allow sharing on behalf of a supervisee" do
      token_user
      u = User.create
      User.link_supervisor_to_user(@user, u)
      utterance = Utterance.create(:user => @user)
      post :share, params: {:utterance_id => utterance.global_id, :email => 'bob@example.com'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['shared']).to eq(true)
    end
    
    it "should allow sharing to a supervisee's supervisor" do
      token_user
      com = User.create
      sup = User.create
      User.link_supervisor_to_user(@user, com)
      User.link_supervisor_to_user(sup, com)
      utterance = Utterance.create(:user => @user)
      post :share, params: {:utterance_id => utterance.global_id, :user_id => sup.global_id, :sharer_id => com.global_id}
      json = assert_success_json
      expect(json['shared']).to eq(true)
      expect(json['details']['from']).to eq(com.global_id)
      expect(json['details']['to']).to eq(sup.global_id)
    end

    it "should add a notification to the supervisor's feed" do
      token_user
      sup = User.create
      User.link_supervisor_to_user(sup, @user)
      utterance = Utterance.create(:user => @user, :data => {'sentence' => 'bacon free piglet'})
      post :share, params: {:utterance_id => utterance.global_id, :supervisor_id => sup.global_id}
      json = JSON.parse(response.body)
      expect(json['shared']).to eq(true)
      Worker.process_queues
      Worker.process_queues
      sup.reload
      expect(sup.settings['user_notifications']).to_not eq(nil)
      expect(sup.settings['user_notifications'].length).to eq(1)
      expect(sup.settings['user_notifications'][0]['text']).to eq('bacon free piglet')
      expect(sup.settings['user_notifications'][0]['sharer_user_name']).to eq(@user.user_name)
    end
    
    it "should return error on error" do
      token_user
      utterance = Utterance.create(:user => @user)
      post :share, params: {:utterance_id => utterance.global_id, :supervisor_id => 1234}
      assert_error('utterance share failed')
    end
  end
  
  describe "GET show" do
    it "should not require api token" do
      u = Utterance.create(:data => {:button_list => [{label: 'ok'}], :sentence => 'ok'})
      get :show, params: {:id => u.global_id}
      expect(response).to be_success
    end
    
    it "should error gracefully if not found" do
      get :show, params: {:id => "abc"}
      assert_not_found
    end
    
    it "should return a json response" do
      u = Utterance.create(:data => {:button_list => [{label: 'ok'}], :sentence => 'ok'})
      get :show, params: {:id => u.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['utterance']['id']).not_to eq(nil)
      expect(json['utterance']['link']).not_to eq(nil)
      expect(json['utterance']['button_list']).not_to eq(nil)
      expect(json['utterance']['sentence']).not_to eq(nil)
      expect(json['utterance']['image_url']).not_to eq(nil)
      expect(json['utterance']['user']).to eq(nil)
      expect(json['utterance']['permissions']).to eq(nil)
    end
  end
end
