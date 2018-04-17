require 'spec_helper'

describe Api::BadgesController, :type => :controller do
  describe "index" do
    it "should require an api token" do
      get 'index'
      assert_missing_token
    end
    
    it "should require an existing user" do
      token_user
      get 'index', params: {:user_id => 'asdf'}
      assert_not_found('asdf')
    end

    it "should require authorization" do
      token_user
      u = User.create
      get 'index', params: {:user_id => u.global_id}
      assert_unauthorized
    end
    
    it "should limit to highlighted results without supervisor authorization" do
      token_user
      u = User.create(:settings => {'public' => true})
      b = UserBadge.create(:user => u, :highlighted => true)
      b2 = UserBadge.create(:user => u)
      get 'index', params: {:user_id => u.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['badge'].length).to eq(1)
      expect(json['badge'][0]['id']).to eq(b.global_id)
    end
    
    it "should filter by goal if set" do
      token_user
      g = UserGoal.create(:user => @user)
      b = UserBadge.create(:user => @user, :user_goal => g)
      get 'index', params: {:user_id => @user.global_id, :goal_id => g.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['badge'].length).to eq(1)
      expect(json['badge'][0]['id']).to eq(b.global_id)
    end
    
    it "should require a valid goal" do
      token_user
      get 'index', params: {:user_id => @user.global_id, :goal_id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require goal editing permission" do
      token_user
      u = User.create
      g = UserGoal.create(:user => u)
      get 'index', params: {:user_id => @user.global_id, :goal_id => g.global_id}
      assert_unauthorized
    end
    
    it "should return a paginated result" do
      token_user
      50.times do |i|
        b = UserBadge.create(:user => @user)
      end
      get 'index', params: {:user_id => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['badge'].length).to eq(10)
      expect(json['meta']['more']).to eq(true)
    end
    
    it "should filter by superseded if not filtering by goal" do
      token_user
      b = UserBadge.create(:user => @user)
      b2 = UserBadge.create(:user => @user, :superseded => true)
      get 'index', params: {:user_id => @user.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['badge'].length).to eq(1)
      expect(json['badge'][0]['id']).to eq(b.global_id)
    end
    
    it "should filter by earned if specified" do
      token_user
      b = UserBadge.create(:user => @user)
      b2 = UserBadge.create(:user => @user, :earned => true)
      get 'index', params: {:user_id => @user.global_id, earned: true}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['badge'].length).to eq(1)
      expect(json['badge'][0]['id']).to eq(b2.global_id)
    end
    
    it "should filter to recently-earned (including supervisees) if specified" do
      token_user
      b = UserBadge.create(:user => @user)
      b2 = UserBadge.create(:user => @user, :earned => true)
      b3 = UserBadge.create(:user => @user, :earned => true)
      b3.data['earn_recorded'] = 6.months.ago.iso8601
      b3.save
      b4 = UserBadge.create(:user => @user, :superseded => true)
      UserBadge.where(id: b3.id).update_all(updated_at: 6.months.ago)
      get 'index', params: {:user_id => @user.global_id, recent: true}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['badge'].length).to eq(2)
      expect(json['badge'].map{|b| b['id']}.sort).to eq([b.global_id, b2.global_id])
    end
  end
  
  describe "show" do
    it "should require an api token" do
      get 'show', params: {:id => 'asdf'}
      assert_missing_token
    end
    
    it "should require a valid record" do
      token_user
      get 'show', params: {:id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      u = User.create
      b = UserBadge.create(:user => u)
      get 'show', params: {:id => b.global_id}
      assert_unauthorized
    end
    
    it "should return a record" do
      token_user
      b = UserBadge.create(:user => @user)
      get 'show', params: {:id => b.global_id}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['badge']).to_not eq(nil)
      expect(json['badge']['id']).to eq(b.global_id)
    end
  end

  describe "update" do
    it "should require an api token" do
      put 'update', params: {:id => 'asdf'}
      assert_missing_token
    end
    
    it "should require a valid record" do
      token_user
      put 'update', params: {:id => 'asdf'}
      assert_not_found('asdf')
    end
    
    it "should require authorization" do
      token_user
      u = User.create
      b = UserBadge.create(:user => u)
      put 'update', params: {:id => b.global_id, :badge => {'highlighted' => true}}
      assert_unauthorized
    end
    
    it "should update the record" do
      token_user
      b = UserBadge.create(:user => @user)
      put 'update', params: {:id => b.global_id, :badge => {'highlighted' => true}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['badge']['id']).to eq(b.global_id)
      expect(json['badge']['highlighted']).to eq(true)
      expect(b.reload.highlighted).to eq(true)
    end
  end
end
