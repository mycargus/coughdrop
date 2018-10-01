require 'spec_helper'

describe Api::GiftsController, :type => :controller do
  describe "show" do
    it "should not require an access token" do
      get :show, params: {:id => 'asdf'}
      expect(response.success?).not_to eq(true)
      json = JSON.parse(response.body)
      expect(response.code).to eq("404")
      expect(json['error']).to eq("Record not found")
    end
    
    it "should error gracefully on a missing gift" do
      get :show, params: {:id => 'asdf'}
      expect(response.success?).not_to eq(true)
      json = JSON.parse(response.body)
      expect(response.code).to eq("404")
      expect(json['error']).to eq("Record not found")
    end
    
    it "should not return an already-redeemed gift" do
      g = GiftPurchase.create
      g.active = false
      g.save
      
      get :show, params: {:id => g.code}
      expect(response.success?).not_to eq(true)
      json = JSON.parse(response.body)
      expect(response.code).to eq("404")
      expect(json['error']).to eq("Record not found")
    end
    
    it "should return a gift record" do
      token_user
      g = GiftPurchase.create(code: '5710897589375081751728957215782317582713057231857239751907582')
      get :show, params: {:id => g.code}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(response.code).to eq("200")
      expect(json['gift']['id']).to eq("#{g.code}::#{g.code_verifier}")
    end
    
    it "should be forgiving on capitalization and o's for 0's" do
      token_user
      g = GiftPurchase.new
      g.code = 'abcd0002587208957238957230895782375892735729087823758723895720397238578923709827057237'
      g.save
      get :show, params: {:id => 'ABcD0Oo2587208957238957230895782375892735729087823758723895720397238578923709827057237'}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(response.code).to eq("200")
      expect(json['gift']['id']).to eq("#{g.code}::#{g.code_verifier}")
    end
  end
  
  describe "index" do
    it "should require an api token" do
      get :index
      assert_missing_token
    end
    
    it "should require admin permission" do
      token_user
      get :index
      assert_unauthorized
    end
    
    it "should return a paginated list" do
      token_user
      org = Organization.create(:admin => true)
      org.add_manager(@user.user_name, true)
      get :index
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['gift']).to eq([])
      expect(json['meta']['offset']).to eq(0)
    end
  end
  
  describe "create" do
    it "should require an api token" do
      post :create, params: {gift: {}}
      assert_missing_token
    end
    
    it "should require admin permission" do
      token_user
      post :create, params: {gift: {}}
      assert_unauthorized
    end
    
    it "should create bulk purchase items" do
      token_user
      org = Organization.create(:admin => true)
      org.add_manager(@user.user_name, true)
      post :create, params: {gift: {
        'licenses' => 4,
        'amount' => 250,
        'email' => 'org@example.com',
        'memo' => 'cool stuff',
        'bacon' => 'is good',
        'organization' => 'cool org'
      }}
      expect(response).to be_success
      json = JSON.parse(response.body)
      gift = GiftPurchase.find_by_code(json['gift']['code'])
      expect(gift).to_not eq(nil)
      expect(json['gift']['code']).to eq(gift.code)
      expect(json['gift']['email']).to eq('org@example.com')
      expect(json['gift']['licenses']).to eq('4')
      expect(json['gift']['amount']).to eq('250')
      expect(json['gift']['memo']).to eq('cool stuff')
      expect(json['gift']['bacon']).to eq(nil)
      expect(json['gift']['organization']).to eq('cool org')
    end
    
    it "should create gift code items" do
      token_user
      org = Organization.create(:admin => true)
      org.add_manager(@user.user_name, true)
      post :create, params: {gift: {
        'email' => 'org@example.com',
        'gift_name' => 'cool gift',
        'seconds' => 2.years.to_i.to_s
      }}
      expect(response).to be_success
      json = JSON.parse(response.body)
      gift = GiftPurchase.find_by_code(json['gift']['code'])
      expect(gift).to_not eq(nil)
      expect(json['gift']['code']).to eq(gift.code)
      expect(json['gift']['email']).to eq(nil)
      expect(json['gift']['gift_name']).to eq('cool gift')
      expect(json['gift']['duration']).to eq('2 years')
    end
  end
  
  describe "destroy" do
    it "should require an api token" do
      delete :destroy, params: {id: 'asdf'}
      assert_missing_token
    end
    
    it "should require admin permission" do
      token_user
      delete :destroy, params: {id: 'asdf'}
      assert_unauthorized
    end

    it "should require a valid gift" do
      token_user
      org = Organization.create(:admin => true)
      org.add_manager(@user.user_name, true)
      delete :destroy, params: {id: 'asdf'}
      assert_not_found('asdf')
    end
    
    
    it "should delete the gift" do
      token_user
      org = Organization.create(:admin => true)
      org.add_manager(@user.user_name, true)
      g = GiftPurchase.create(active: true)
      expect(g.reload.active).to eq(true)
      delete :destroy, params: {id: g.code}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['gift']['code']).to eq(g.code)
      expect(GiftPurchase.count).to eq(1)
      expect(g.reload.active).to eq(false)
    end
  end
end
