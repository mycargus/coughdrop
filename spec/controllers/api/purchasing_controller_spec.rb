require 'spec_helper'

describe Api::PurchasingController, :type => :controller do
  describe "event" do
    it "should call the purchasing library and return the result" do
      expect(Purchasing).to receive(:subscription_event){|req|
        expect(req.params[:a]).to eq('1')
        expect(req.params[:b]).to eq('asdf')
      }.and_return({
        :status => 200,
        :data => {:a => 1}
      })
      post :event, params: {:a => 1, :b => 'asdf'}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['a']).to eq(1)
    end
  end
  
  describe "purchase_gift" do
    it "should call the purchasing library and return a progress object" do
      token_user
      p = Progress.create
      expect(Progress).to receive(:schedule).with(GiftPurchase, :process_subscription_token, {'id' => 'abc'}, {'type' => 'long_term_150', 'email' => nil, 'user_id' => @user.global_id, 'code' => nil}).and_return(p)
      post :purchase_gift, params: {:token => {'id' => 'abc'}, :type => 'long_term_150'}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['progress']).not_to eq(nil)
    end
    
    it "should pass the code of specified" do
      token_user
      p = Progress.create
      expect(Progress).to receive(:schedule).with(GiftPurchase, :process_subscription_token, {'id' => 'abc'}, {'type' => 'long_term_150', 'email' => nil, 'user_id' => @user.global_id, 'code' => 'asdfasdf'}).and_return(p)
      post :purchase_gift, params: {:token => {'id' => 'abc'}, :type => 'long_term_150', :code => 'asdfasdf'}
      expect(response.success?).to eq(true)
      json = JSON.parse(response.body)
      expect(json['progress']).not_to eq(nil)
    end
  end
end
