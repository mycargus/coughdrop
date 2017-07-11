require 'spec_helper'

describe Device, :type => :model do
  describe "paper trail" do
    it "should make sure paper trail is doing its thing"
  end
  
  describe "generate_defaults" do
    it "should generate default values" do
      d = Device.new
      d.generate_defaults
      expect(d.settings).to eq({
      })
      d.device_key = 'default'
      d.developer_key_id = 0
      d.generate_defaults
      expect(d.settings).to eq({
        'name' => 'Web browser for Desktop'
      })
      
      d2 = Device.new
      d2.developer_key_id = 0
      d2.device_key = '1.241125 Cool One'
      d2.generate_defaults
      expect(d2.settings['name']).to eq('Cool One')
    end
  end

  describe "update_user_device_name" do
    it "should actually do something"
  end
  
  describe "device_key" do
    it "should correctly respond to default_device?" do
      d = Device.new
      expect(d.default_device?).to eq(false)
      d.device_key = 'default'
      expect(d.default_device?).to eq(false)
      d.developer_key_id = 2
      expect(d.default_device?).to eq(false)
      d.developer_key_id = 0
      expect(d.default_device?).to eq(true)
    end
    
    it "should always use 'default' for the default device" do
      d = Device.new
      expect { d.unique_device_key }.to raise_error("must be saved first")
      d.id = 123
      expect { d.unique_device_key }.to raise_error("missing developer_key_id")
      d.device_key = 'default'
      d.developer_key_id = 0
      expect(d.unique_device_key).to eq('default')
    end
    
    it "should include the developer key id in non-default devices" do
      d = Device.new
      d.id = 234
      d.device_key = 'default'
      d.developer_key_id = 1
      expect(d.unique_device_key).to eq('default_1')
      d.device_key = 'bacon'
      expect(d.unique_device_key).to eq('bacon_1')
    end
  end
    
  describe "generate_token!" do
    it "should error if the device isn't already saved" do
      d = Device.new
      expect { d.generate_token! }.to raise_error("device must already be saved")
    end
    
    it "should generate a new key" do
      d = Device.create
      d.generate_token!
      expect(d.settings['keys']).not_to be_nil
      expect(d.settings['keys'].length).to eq(1)
      expect(d.settings['keys'][0]['timestamp']).to be > Time.now.to_i - 100
      expect(d.settings['keys'][0]['value']).not_to eq(nil)
    end
    
    it "should generate a short key when no long-key specified" do
      d = Device.create(:device_key => 'default', :developer_key_id => 0)
      d.generate_token!
      expect(d.settings['keys']).not_to be_nil
      expect(d.settings['keys'].length).to eq(1)
      expect(d.settings['keys'][0]['timestamp']).to be > Time.now.to_i - 100
      expect(d.settings['keys'][0]['value']).not_to eq(nil)
      expect(d.settings['keys'][0]['timeout']).to eq(24.hours.to_i)
    end
    
    it "should generate a short key for non-default devices when not specified" do
      d = Device.create()
      d.generate_token!
      expect(d.settings['keys']).not_to be_nil
      expect(d.settings['keys'].length).to eq(1)
      expect(d.settings['keys'][0]['timestamp']).to be > Time.now.to_i - 100
      expect(d.settings['keys'][0]['value']).not_to eq(nil)
      expect(d.settings['keys'][0]['timeout']).to eq(24.hours.to_i)
    end
    
    it "should generate a long key for default devices if specified" do
      d = Device.create(:device_key => 'default', :developer_key_id => 0)
      d.generate_token!(true)
      expect(d.settings['keys']).not_to be_nil
      expect(d.settings['keys'].length).to eq(1)
      expect(d.settings['keys'][0]['timestamp']).to be > Time.now.to_i - 100
      expect(d.settings['keys'][0]['value']).not_to eq(nil)
      expect(d.settings['keys'][0]['timeout']).to eq(28.days.to_i)
    end
    
    it "should track token generation history" do
      d = Device.create(:device_key => 'default', :developer_key_id => 0)
      expect(d.settings['token_history']).to eq(nil)
      d.generate_token!
      expect(d.settings['token_history']).not_to eq(nil)
      expect(d.settings['token_history'].length).to eq(1)
      expect(d.settings['token_history'][0]).to be > 10.seconds.ago.to_i
      d.generate_token!
      expect(d.settings['token_history'].length).to eq(2)
      d.generate_token!
      expect(d.settings['token_history'].length).to eq(3)
    end
    
    it "should allow only the system-generated devices to have multiple keys" do
      d = Device.create(:device_key => 'default', :developer_key_id => 0)
      expect(d.default_device?).to eq(true)
      expect(d.system_generated?).to eq(true)
      d.generate_token!
      d.generate_token!
      d.generate_token!
      expect(d.settings['keys']).not_to be_nil
      expect(d.settings['keys'].length).to eq(3)
      
      d.device_key = 'bob'
      expect(d.default_device?).to eq(false)
      expect(d.system_generated?).to eq(true)
      d.generate_token!
      expect(d.settings['keys'].length).to eq(4)
      
      d.developer_key_id = 1
      expect(d.default_device?).to eq(false)
      expect(d.system_generated?).to eq(false)
      d.generate_token!
      expect(d.settings['keys'].length).to eq(1)
    end
    
    it "should flush out old keys as part of the generation process" do
      d = Device.create(:device_key => 'default', :developer_key_id => 0)
      d.settings['keys'] = [
        {'value' => 'bob', 'last_timestamp' => 12.days.ago.to_i},
        {'value' => 'fred', 'last_timestamp' => 1.second.ago.to_i}
      ]
      d.generate_token!
      expect(d.settings['keys'].length).to eq(2)
      expect(d.settings['keys'][0]['value']).to eq('fred')
    end
  end

  describe "logout!" do
    it "should remove all existing keys" do
      d = Device.new
      d.settings = {'keys' => [{}, {}, {}]}
      d.logout!
      expect(d.settings).to eq({'keys' => []})
    end
  end
  
  describe "clean_old_keys" do
    it "should remove old tokens" do
      d = Device.new
      d.settings = {}
      d.settings['keys'] = [{'value' => 'bob', 'last_timestamp' => 30.days.ago.to_i}, {'value' => 'fred', 'last_timestamp' => 1.second.ago.to_i}]
      d.clean_old_keys
      expect(d.settings['keys']).to eq([{'value' => 'fred', 'last_timestamp' => 1.second.ago.to_i}])
    end
    
    it "should remove tokens based on their timeout if provided" do
      d = Device.new
      d.settings = {}
      d.settings['keys'] = [{'value' => 'bob', 'last_timestamp' => 30.days.ago.to_i, 'timeout' => 40.days.to_i}, {'value' => 'fred', 'last_timestamp' => 1.hour.ago.to_i, 'timeout' => 10.minutes.to_i}]
      d.clean_old_keys
      expect(d.settings['keys']).to eq([{'value' => 'bob', 'last_timestamp' => 30.days.ago.to_i, 'timeout' => 40.days.to_i}])
    end
  end

  describe "valid_token?" do
    it "should return a boolean" do
      d = Device.new
      expect(d.valid_token?('bob')).to eq(false)
      d.settings = {}
      d.settings['keys'] = [{'value' => 'bob', 'last_timestamp' => 1.second.ago.to_i}]
      expect(d.valid_token?('bob')).to eq(true)
      d.settings['keys'] = [{'value' => 'bob', 'last_timestamp' => 1.second.ago.to_i}, {'value' => 'fred', 'last_timestamp' => 1.second.ago.to_i}]
      expect(d.valid_token?('bob')).to eq(true)
      expect(d.valid_token?('fred')).to eq(true)
    end
    
    it "should ignore old tokens" do
      d = Device.new
      d.settings = {}
      d.settings['keys'] = [{'value' => 'bob', 'last_timestamp' => 30.days.ago.to_i}, {'value' => 'fred', 'last_timestamp' => 1.second.ago.to_i}]
      expect(d.valid_token?('bob')).to eq(false)
      expect(d.valid_token?('fred')).to eq(true)
    end
    
    it "should update timestamp periodically on token user" do
      d = Device.new
      d.settings = {}
      d.settings['keys'] = [{'value' => 'bob', 'last_timestamp' => 35.minutes.ago.to_i}]
      expect(d.valid_token?('bob')).to eq(true)
      d.reload
      expect(d.settings['keys'][0]['last_timestamp']).to be > 10.seconds.ago.to_i
    end
    
    it "should update the app version if passed in" do
      d = Device.new
      d.settings = {}
      d.settings['keys'] = [{'value' => 'bob', 'last_timestamp' => 35.minutes.ago.to_i}]
      expect(d.valid_token?('bob', '2011.01.01')).to eq(true)
      d.reload
      expect(d.settings['keys'][0]['last_timestamp']).to be > 10.seconds.ago.to_i
      expect(d.settings['app_version']).to eq('2011.01.01')
      expect(d.settings['app_versions']).not_to eq(nil)
      expect(d.settings['app_versions'].length).to eq(1)
      expect(d.settings['app_versions'][0][0]).to eq('2011.01.01')
      expect(d.settings['app_versions'][0][1]).to be > Time.now.to_i - 5
      expect(d.settings['app_versions'][0][1]).to be < Time.now.to_i + 5

      expect(d.valid_token?('bob')).to eq(true)
      expect(d.settings['app_versions'].length).to eq(1)

      expect(d.valid_token?('bob', '2012.01.01')).to eq(true)
      expect(d.settings['app_versions'].length).to eq(2)
      expect(d.settings['app_versions'][1][0]).to eq('2012.01.01')
      expect(d.settings['app_versions'][1][1]).to be > Time.now.to_i - 5
      expect(d.settings['app_versions'][1][1]).to be < Time.now.to_i + 5
    end
    
    it "should always return false for disabled tokens" do
      d = Device.new
      expect(d.valid_token?('bob')).to eq(false)
      d.settings = {}
      d.settings['keys'] = [{'value' => 'bob', 'last_timestamp' => 1.second.ago.to_i}]
      expect(d.valid_token?('bob')).to eq(true)
      d.settings['disabled'] = true
      expect(d.valid_token?('bob')).to eq(false)
      d.settings['keys'] = [{'value' => 'bob', 'last_timestamp' => 1.second.ago.to_i}, {'value' => 'fred', 'last_timestamp' => 1.second.ago.to_i}]
      expect(d.valid_token?('bob')).to eq(false)
      expect(d.valid_token?('fred')).to eq(false)
    end
  end

  describe "token" do
    it "should return the latest token" do
      d = Device.new
      d.settings = {}
      d.settings['keys'] = [{'value' => 'ham', 'last_timestamp' => 1.second.ago.to_i}, {'value' => 'bacon', 'last_timestamp' => 1.second.ago.to_i}]
      expect(d.token).to eq('bacon')
      expect(d.token).to eq('bacon')
    end
    
    it "should ignore old tokens" do
      d = Device.new
      d.settings = {}
      d.settings['keys'] = [{'value' => 'ham', 'last_timestamp' => 1.second.ago.to_i}, {'value' => 'bacon', 'last_timestamp' => 30.days.ago.to_i}]
      expect(d.token).to eq('ham')
    end
    
    it "should generate a token if none are yet available" do
      d = Device.create
      d.settings = {}
      d.settings['keys'] = [{'value' => 'bacon', 'last_timestamp' => 30.days.ago.to_i}]
      expect(d.token).not_to eq('ham')
      expect(d.token.length).to be > 24
      expect(d.settings['keys'].length).to eq(1)
      
      d.settings['keys'] = []
      expect(d.token.length).to be > 24
      expect(d.settings['keys'].length).to eq(1)
    end
  end
          
  it "should securely serialize settings" do
    d = Device.new
    d.generate_defaults
    settings = d.settings
    expect(GoSecure::SecureJson).to receive(:dump).with(d.settings)
    d.save
  end
  

  describe "disabled?" do
    it "should return the correct value" do
      d = Device.new
      expect(d.disabled?).to eq(false)
      d.settings = {}
      expect(d.disabled?).to eq(false)
      d.settings['disabled'] = false
      expect(d.disabled?).to eq(false)
      d.settings['disabled'] = true
      expect(d.disabled?).to eq(true)
    end
  end
  
  describe "permission_scopes" do
    it "should return nothing if disabled" do
      d = Device.new
      d.settings = {'disabled' => true}
      expect(d.permission_scopes).to eq([])
      d.settings['permission_scopes'] = ['a', 'b', 'c']
      expect(d.permission_scopes).to eq([])
    end
    
    it "should return 'full' if not an integration" do
      d = Device.new
      expect(d.permission_scopes).to eq(['full'])
    end
    
    it "should return defined scopes if for an integration" do
      d = Device.new
      d.user_integration_id = 1
      expect(d.permission_scopes).to eq([])
      d.settings = {'permission_scopes' => ['a', 'b']}
      expect(d.permission_scopes).to eq(['a', 'b'])
    end
  end
  
  describe "inactivity_timeout" do
    it "should return the correct value" do
      d = Device.new
      expect(d.inactivity_timeout).to eq(24.hours.to_i)
      expect(d.inactivity_timeout(true)).to eq(28.days.to_i)
      d.user_integration_id = 1
      expect(d.inactivity_timeout).to eq(6.months.to_i)
      expect(d.inactivity_timeout(true)).to eq(6.months.to_i)
    end
  end
  
  describe "invalidate_keys!" do
    it "should invalidate keys" do
      d = Device.create
      d.generate_token!
      expect(d.settings['keys']).not_to be_nil
      expect(d.settings['keys'].length).to eq(1)
      
      d.invalidate_keys!
      expect(d.reload.settings['keys']).to eq([])
    end
  end
end
