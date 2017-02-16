require 'spec_helper'

describe JsonApi::Integration do
  it "should have defined pagination defaults" do
    expect(JsonApi::Integration::TYPE_KEY).to eq('integration')
    expect(JsonApi::Integration::DEFAULT_PAGE).to eq(10)
    expect(JsonApi::Integration::MAX_PAGE).to eq(25)
  end

  describe "build_json" do
    it "should not include unlisted settings" do
      i = UserIntegration.create
      i.settings['hat'] = 'white'
      expect(JsonApi::Integration.build_json(i).keys).to_not be_include('hat')
    end
    
    it "should return appropriate attributes" do
      i = UserIntegration.create
      i.settings['name'] = 'some thing'
      expect(JsonApi::Integration.build_json(i)['id']).to eq(i.global_id)
      expect(JsonApi::Integration.build_json(i)['name']).to eq('some thing')
    end
    
    it "should include integration information only for custom integrations" do
      u = User.create
      i = UserIntegration.create(:user => u)
      d = i.device
      expect(d).to_not eq(nil)
      expect(d.user).to eq(u)
      i.settings['custom_integration'] = true
      hash = JsonApi::Integration.build_json(i)
      expect(hash['access_token']).to_not eq(nil)
      expect(hash['access_token']).to eq(d.token)
      expect(hash['token']).to_not eq(nil)
      expect(hash['token']).to eq(i.settings['token'])
    end
    
    it "should include truncated keys after 24 hours" do
      u = User.create
      i = UserIntegration.create(:user => u)
      i.created_at = 6.days.ago
      i.settings['custom_integration'] = true
      hash = JsonApi::Integration.build_json(i)
      expect(hash['access_token']).to eq(nil)
      expect(hash['token']).to eq(nil)
      expect(hash['truncated_access_token']).to_not eq(nil)
      expect(hash['truncated_token']).to_not eq(nil)
    end
    
    it "should include user settings" do
      u = User.create
      ui = UserIntegration.create(user: u)
      ui.settings['user_settings'] = {
        'a' => {
          'label' => 'A',
          'value' => 'asdf'
        },
        'b' => {
          'label' => 'B',
          'value' => 'asdf',
          'type' => 'password'
        }
      }
      hash = JsonApi::Integration.build_json(ui)
      expect(hash['user_settings']).to_not eq(nil)
      puts hash['user_settings'].to_json
      expect(hash['user_settings'][0]['name']).to eq('a')
      expect(hash['user_settings'][0]['label']).to eq('A')
      expect(hash['user_settings'][0]['value']).to eq('asdf')
      expect(hash['user_settings'][1]['name']).to eq('b')
      expect(hash['user_settings'][1]['label']).to eq('B')
      expect(hash['user_settings'][1]['value']).to eq(nil)
      expect(hash['user_settings'][1]['protected']).to eq(true)
    end
    
    it "should include user parameters for templates" do
      ui = UserIntegration.create(template: true, integration_key: 'keyed')
      ui.settings['user_parameters'] = [
        {
          'name' => 'a',
          'default_value' => 'aaa',
          'label' => 'A'
        },
        {
          'name' => 'b',
          'default_value' => 'bbb',
          'type' => 'password',
          'label' => 'B',
          'something' => 'nunya'
        }
      ]
      hash = JsonApi::Integration.build_json(ui)
      expect(hash['template']).to eq(true)
      expect(hash['user_parameters']).to eq([
        {
          'name' => 'a',
          'default_value' => 'aaa',
          'label' => 'A',
          'type' => 'text'
        },
        {
          'name' => 'b',
          'default_value' => 'bbb',
          'type' => 'password',
          'label' => 'B'
        }
      ])
    end
  end
end
