require 'spec_helper'

describe GiftPurchase, :type => :model do
  it "should generate defaults" do
    g = GiftPurchase.new
    g.generate_defaults
    expect(g.active).to eq(true)
    expect(g.settings).to eq({})
  end
  
  it "should generate a unique code on create" do
    expect(GoSecure).to receive(:nonce).with('gift_code').and_return('abcdefghij').exactly(6).times
    g = GiftPurchase.create
    expect(g.code).to eq('abcdefgh')
    g2 = GiftPurchase.create
    expect(g2.code).to eq('abcdefghi')
  end
  
  it "should trigger a notification on create with a giver specified" do
    methods = []
    expect(SubscriptionMailer).to receive(:schedule_delivery){|method, id, action|
      methods << method
      if method == :gift_created
        expect(id).to_not be_nil
        expect(action).to be_nil
      elsif method == :gift_updated
        expect(id).to_not be_nil
        expect(action).to eq('purchase')
      end
    }.exactly(2).times
    g = GiftPurchase.create
    g2 = GiftPurchase.create(:settings => {'giver_email' => 'bob@example.com'})
    expect(methods).to eq([])
    g2.notify_of_creation
    expect(methods).to eq([:gift_created, :gift_updated])
  end
  
  describe "duration" do
    it "should return a reasonable message when no duration available" do
      g = GiftPurchase.new
      expect(g.duration).to eq("no time specified")
    end
    
    it "should return a multi-year duration clearly" do
      g = GiftPurchase.new(:settings => {'seconds_to_add' => 5.years.to_i})
      expect(g.duration).to eq('5 years')
    end
    
    it "should return a complex duration clearly" do
      g = GiftPurchase.new(:settings => {'seconds_to_add' => 2.years.to_i + 3.weeks.to_i + 2.days.to_i + 8.hours.to_i + 12.minutes.to_i + 99.seconds.to_i})
      expect(g.duration).to eq('2 years, 23 days, 8 hours, 13 minutes')
    end
  end
  
  it "should return the receiving user" do
    u = User.create
    g = GiftPurchase.new
    expect(g.receiver).to eq(nil)
    
    g.settings = {'receiver_id' => u.global_id}
    expect(g.receiver).to eq(u)
  end
  
  it "should return the giving user" do
    u = User.create
    g = GiftPurchase.new
    expect(g.receiver).to eq(nil)
    
    g.settings = {'giver_id' => u.global_id}
    expect(g.giver).to eq(u)
  end
  
  it "should generate correctly from provided parameters" do
    u = User.create
    g = GiftPurchase.process_new({}, {
      'giver' => u, 
      'email' => 'bob@example.com',
      'customer_id' => '12345',
      'token_summary' => 'no card',
      'plan_id' => 'long_term_150',
      'purchase_id' => '23456',
      'bacon' => '1234'
    })
    expect(g.settings['giver_id']).to eq(u.global_id)
    expect(g.settings['giver_email']).to eq('bob@example.com')
    expect(g.settings['customer_id']).to eq('12345')
    expect(g.settings['token_summary']).to eq('no card')
    expect(g.settings['plan_id']).to eq('long_term_150')
    expect(g.settings['purchase_id']).to eq('23456')
    expect(g.settings['bacon']).to eq(nil)
    
    g = GiftPurchase.process_new({
      'email' => 'fred@example.com'
    }, {
      'token_summary' => 'no card',
      'plan_id' => 'long_term_150',
      'purchase_id' => '23456',
      'bacon' => '1234'
    })
    expect(g.settings['giver_id']).to eq(nil)
    expect(g.settings['giver_email']).to eq('fred@example.com')
    expect(g.settings['customer_id']).to eq(nil)
    expect(g.settings['token_summary']).to eq('no card')
    expect(g.settings['plan_id']).to eq('long_term_150')
    expect(g.settings['purchase_id']).to eq('23456')
    expect(g.settings['bacon']).to eq(nil)
  end
  
  it "should process bulk purchase settings" do
    g = GiftPurchase.process_new({
      'licenses' => 4,
      'amount' => 234,
      'organization' => 'asdf',
      'email' => 'bob@example.com'
    }, {
    })
    expect(g.settings['licenses']).to eq(4)
    expect(g.settings['amount']).to eq(234)
    expect(g.settings['organization']).to eq('asdf')
    expect(g.settings['email']).to eq('bob@example.com')
  end
  
  it "should return correct value for purchased?" do
    g = GiftPurchase.new(settings: {})
    expect(g.purchased?).to eq(false)
    g.settings['purchase_id']  = 'asdf'
    expect(g.purchased?).to eq(true)
  end
  
  it "should return correct value for bulk_purchase?" do
    g = GiftPurchase.process_new({
      'licenses' => 4,
      'amount' => 234,
      'organization' => 'asdf',
      'email' => 'bob@example.com'
    }, {
    })
    expect(g.settings['licenses']).to eq(4)
    expect(g.settings['amount']).to eq(234)
    expect(g.settings['organization']).to eq('asdf')
    expect(g.settings['email']).to eq('bob@example.com')
    expect(g.bulk_purchase?).to eq(true)
    g = GiftPurchase.new
    expect(g.bulk_purchase?).to eq(false)
  end
  
  it "should inactivate bulk purchases when redeemed" do
    g = GiftPurchase.create
    g.settings['licenses'] = 4
    g.save
    expect(g.active).to eq(true)
    g.settings['purchase_id'] = 'asdf'
    g.save
    expect(g.active).to eq(false)
  end
end
