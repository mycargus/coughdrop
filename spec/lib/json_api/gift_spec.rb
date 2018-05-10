require 'spec_helper'

describe JsonApi::Gift do
  it "should have defined pagination defaults" do
    expect(JsonApi::Gift::TYPE_KEY).to eq('gift')
    expect(JsonApi::Gift::DEFAULT_PAGE).to eq(25)
    expect(JsonApi::Gift::MAX_PAGE).to eq(50)
  end

  describe "build_json" do
    it "should not include unlisted settings" do
      g = GiftPurchase.create(:settings => {'hat' => 'black'})
      expect(JsonApi::Gift.build_json(g).keys).not_to be_include('hat')
    end
    
    it "should return appropriate attributes" do
      g = GiftPurchase.create(:settings => {'hat' => 'black', 'seconds_to_add' => 2.years.to_i})
      expect(JsonApi::Gift.build_json(g)).to eq({
        'id' => g.code,
        'code' => g.code,
        'seconds' => 2.years.to_i,
        'duration' => '2 years',
        'gift_type' => 'user_gift',
        'redeemed_codes' => 0,
        'org_connected' => false,
        'total_codes' => nil,
        'active' => true,
        'amount' => nil,
        'created' => g.created_at.iso8601,
        'memo' => nil,
        'gift_name' => nil,
        'licenses' => nil,
        'organization' => nil,
        'purchased' => false
      })
    end
    
    it "should include receiver information" do
      write_this_test
    end
  end
end
