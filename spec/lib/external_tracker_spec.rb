require 'spec_helper'

describe ExternalTracker do
  describe "track_new_user" do
    it "should do nothing if not allowed" do
      ExternalTracker.track_new_user(nil)
      expect(Worker.scheduled_actions).to eq([])
      
      u = User.create
      u.settings['authored_organization_id'] = 'asdf'
      u.save
      ExternalTracker.track_new_user(u)
      expect(Worker.scheduled_actions).to eq([])
    end
    
    it "should schedule a persistence if allowed" do
      u = User.create
      ExternalTracker.track_new_user(u)
      expect(Worker.scheduled?(ExternalTracker, :persist_new_user, u.global_id)).to eq(true)
    end
  end
  
  describe "persist_new_user" do
    it "should return false if not allowed" do
      u = User.create
      u.settings['authored_organization_id'] = 'asdf'
      u.save
      expect(ExternalTracker.persist_new_user(u.global_id)).to eq(false)
    end
    
    it "should return false if not configured" do
      u = User.create
      ENV['HUBSPOT_KEY'] = nil
      expect(ExternalTracker.persist_new_user(u.global_id)).to eq(false)
    end
    
    it "should return false if no email provided" do
      u = User.create
      ENV['HUBSPOT_KEY'] = 'hubby'
      expect(ExternalTracker.persist_new_user(u.global_id)).to eq(false)
    end
    
    it "should return non-false on success" do
      u = User.create
      u.settings['email'] = 'testing@example.com'
      u.save
      ENV['HUBSPOT_KEY'] = 'hubby'
#       geo = {
#         'country_code' => 'US',
#         'city' => 'Sandy',
#         'region_name' => 'Utah'
#       }
#      expect(Typhoeus).to receive(:get).with('asdf').and_return(OpenStruct.new(body: geo.to_json))
      expect(Typhoeus).to receive(:post).with("https://api.hubapi.com/contacts/v1/contact/?hapikey=hubby", {
        body: {properties: [
          {property: 'email', value: 'testing@example.com' },
          {property: 'firstname', value: 'No'},
          {property: 'lastname', value: 'name'},
          {property: 'city', value: nil},
          {property: 'state', value: nil}
        ]}.to_json,
        headers: {'Content-Type' => 'application/json'}
      }).and_return(OpenStruct.new(code: '201'))
      res = ExternalTracker.persist_new_user(u.global_id)
      expect(res).to eq('201')
    end
    
    it "should check for geo location based on ip address" do
      u = User.create
      u.settings['email'] = 'testing@example.com'
      u.save
      expect(u.devices.count).to eq(0)
      d = Device.create(:user => u)
      d.settings['ip_address'] = '1.2.3.4'
      d.save
      ENV['HUBSPOT_KEY'] = 'hubby'
      geo = {
        'country_code' => 'US',
        'city' => 'Sandy',
        'region_name' => 'Utah'
      }
     expect(Typhoeus).to receive(:get).with("http://api.ipstack.com/1.2.3.4?access_key=#{ENV['IPSTACK_KEY']}").and_return(OpenStruct.new(body: geo.to_json))
      expect(Typhoeus).to receive(:post).with("https://api.hubapi.com/contacts/v1/contact/?hapikey=hubby", {
        body: {properties: [
          {property: 'email', value: 'testing@example.com' },
          {property: 'firstname', value: 'No'},
          {property: 'lastname', value: 'name'},
          {property: 'city', value: 'Sandy'},
          {property: 'state', value: 'Utah'}
        ]}.to_json,
        headers: {'Content-Type' => 'application/json'}
      }).and_return(OpenStruct.new(code: '201'))
      res = ExternalTracker.persist_new_user(u.global_id)
      expect(res).to eq('201')
    end
    
    it "should push to external systems" do
      u = User.create
      u.settings['email'] = 'testing@example.com'
      u.save
      expect(u.devices.count).to eq(0)
      d = Device.create(:user => u)
      d.settings['ip_address'] = '1.2.3.4'
      d.save
      ENV['HUBSPOT_KEY'] = 'hubby'
      geo = {
        'country_code' => 'US',
        'city' => 'Sandy',
        'region_name' => 'Utah'
      }
     expect(Typhoeus).to receive(:get).with("http://api.ipstack.com/1.2.3.4?access_key=#{ENV['IPSTACK_KEY']}").and_return(OpenStruct.new(body: geo.to_json))
      expect(Typhoeus).to receive(:post).with("https://api.hubapi.com/contacts/v1/contact/?hapikey=hubby", {
        body: {properties: [
          {property: 'email', value: 'testing@example.com' },
          {property: 'firstname', value: 'No'},
          {property: 'lastname', value: 'name'},
          {property: 'city', value: 'Sandy'},
          {property: 'state', value: 'Utah'}
        ]}.to_json,
        headers: {'Content-Type' => 'application/json'}
      }).and_return(OpenStruct.new(code: '201'))
      res = ExternalTracker.persist_new_user(u.global_id)
      expect(res).to eq('201')
    end
  end
end
