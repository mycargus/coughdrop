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
        'id' => "#{g.code}::#{g.code_verifier}",
        'code' => g.code,
        'seconds' => 2.years.to_i,
        'duration' => '2 years',
        'gift_type' => 'user_gift',
        'activated_discounts' => 0,
        'discount' => 1.0,
        'expires' => nil,
        'include_extras' => nil,
        'limit' => nil,
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
      g = GiftPurchase.create(:settings => {'hat' => 'black', 'seconds_to_add' => 2.years.to_i, 'total_codes' => 5})
      expect(g.settings['codes']).to_not eq(nil)
      expect(g.settings['codes'].length).to eq(5)
      u = User.create
      g.settings['admin_user_ids'] = [u.global_id]
      g.save!
      u2 = User.create
      code = g.settings['codes'].to_a[1][0]
      code2 = g.settings['codes'].to_a[0][0]
      g.redeem_code!(code, u2)
      expect(g.allows?(u, 'manage')).to eq(true)
      json = JsonApi::Gift.build_json(g, :permissions => u)
      expect(json['id']).to eq("#{g.code}::#{g.code_verifier}")
      expect(json['codes'].length).to eq(5)
      code = json['codes'].detect{|c| c[:code] == code }
      expect(code).to_not eq(nil)
      expect(code[:redeemed]).to eq(true)
      expect(code[:receiver]['id']).to eq(u2.global_id)
      expect(!!json['codes'][0]['redeemed']).to eq(false)
      code = json['codes'].detect{|c| c[:code] == code2 }
      expect(json['duration']).to eq('2 years')
      expect(json['purchased']).to eq(false)
    end

    it 'should include receiver information for discount codes' do
      g = GiftPurchase.create(:settings => {'discount' => 0.5, 'limit' => 15})
      u = User.create
      g.redeem_code!(g.code, u)
      u2 = User.create
      g.redeem_code!(g.code, u2)

      g.settings['admin_user_ids'] = [u.global_id]
      u.save!
      json = JsonApi::Gift.build_json(g, :permissions => u)
      expect(json['activations'].length).to eq(2)
      expect(json['activations'][0][:activated_at]).to be > 5.minutes.ago.utc.iso8601
      expect(json['activations'][0][:receiver]['user_name']).to eq(u.user_name)
      expect(json['activations'][1][:activated_at]).to be > 5.minutes.ago.utc.iso8601
      expect(json['activations'][1][:receiver]['user_name']).to eq(u2.user_name)
    end
  end
end
