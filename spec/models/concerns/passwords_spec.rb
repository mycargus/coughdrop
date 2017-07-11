require 'spec_helper'

describe Passwords, :type => :model do
  describe "password resetting" do
    it "should clean old reset attempts" do
      u = User.new
      u.settings = {}
      u.settings['password_resets'] = [
        {'timestamp' => Time.now.to_i - 100000},
        {'timestamp' => Time.now.to_i - 50000},
        {'timestamp' => Time.now.to_i - 500},
        {'timestamp' => Time.now.to_i - 100},
        {'timestamp' => Time.now.to_i - 100},
        {'timestamp' => Time.now.to_i - 10},
      ]
      u.clean_password_resets
      expect(u.settings['password_resets'].length).to eq(4)
    end
    
    it "should generate a password reset token" do
      u = User.new
      expect(u.generate_password_reset).to eq(true)
      expect(u.settings['password_resets'].length).to eq(1)
      expect(u.settings['password_resets'][0]['timestamp']).to be > (Time.now.to_i - 100)
      expect(u.settings['password_resets'][0]['code']).not_to eq(nil)
    end
    
    it "should fail to generate a reset token if there are too many already generated" do
      u = User.new
      u.settings = {}
      u.settings['password_resets'] = [
        {'timestamp' => Time.now.to_i - 500},
        {'timestamp' => Time.now.to_i - 500},
        {'timestamp' => Time.now.to_i - 500},
        {'timestamp' => Time.now.to_i - 100},
        {'timestamp' => Time.now.to_i - 100},
        {'timestamp' => Time.now.to_i - 10},
      ]
      expect(u.generate_password_reset).to eq(false)
    end
    
    it "should return the latest reset code when requested" do
      u = User.new
      u.settings = {}
      u.settings['password_resets'] = [
        {'timestamp' => Time.now.to_i - 500},
        {'timestamp' => Time.now.to_i - 500},
        {'timestamp' => Time.now.to_i - 500},
        {'timestamp' => Time.now.to_i - 100},
        {'timestamp' => Time.now.to_i - 100, 'code' => 'cheese'},
        {'timestamp' => Time.now.to_i - 10, 'code' => 'coolness'},
      ]
      expect(u.password_reset_code).to eq('coolness')
      u.settings['password_resets'][-1]['timestamp'] = Time.now.to_i - 50000
      expect(u.password_reset_code).to eq('cheese')
    end
    
    it "should generate a reset token when a valid code is provided" do
      u = User.new
      u.settings = {}
      u.settings['password_resets'] = [
        {'timestamp' => Time.now.to_i - 50000, 'code' => 'always'},
        {'timestamp' => Time.now.to_i - 10, 'code' => 'coolness'},
      ]
      expect(u.reset_token_for_code('nothing')).to eq(nil)
      expect(u.reset_token_for_code('always')).to eq(nil)
      expect(u.reset_token_for_code('coolness')).not_to eq(nil)
      expect(u.settings['password_resets'][-1]['token']).not_to eq(nil)
    end
    
    it "should confirm the reset token for any still-valid reset attempt" do
      u = User.new
      u.settings = {}
      u.settings['password_resets'] = [
        {'timestamp' => Time.now.to_i - 50000, 'code' => 'always'},
        {'timestamp' => Time.now.to_i - 10, 'code' => 'coolness'},
      ]
      token = u.reset_token_for_code('coolness')
      expect(token).not_to eq(nil)
      expect(u.valid_reset_token?(token)).to eq(true)
      expect(u.valid_reset_token?('abcdef')).to eq(false)

      u.settings['password_resets'] = [
        {'timestamp' => Time.now.to_i - 50000, 'code' => 'always', 'token' => 'qwert'},
        {'timestamp' => Time.now.to_i - 10, 'code' => 'coolness', 'token' => 'werty'},
      ]
      expect(u.valid_reset_token?('qwert')).to eq(false)
      expect(u.valid_reset_token?('werty')).to eq(true)
    end
  end
  
  describe "generate_password" do
    it "should generate a password" do
      u = User.new
      u.generate_password("hippo")
      expect(u.settings['password']['hash_type']).to eq('pbkdf2-sha256')
      expect(u.settings['password']['hashed_password']).not_to eq(nil)
      expect(u.settings['password']['salt']).not_to eq(nil)
      
      expect(GoSecure).to receive(:generate_password).with("bacon")
      User.new.generate_password("bacon")
    end
  end
  
  describe "valid_password?" do
    it "should check the password" do
      u = User.new
      u.generate_password("I love to eat apples and bananas")
      pw = u.settings['password']
      expect(u.valid_password?("chicken")).to eq(false)
      expect(u.valid_password?("I love to eat apples and bananas")).to eq(true)
      expect(u.valid_password?("I love to eat fried chicken")).to eq(false)
      expect(u.valid_password?("I love to eat apples and bananas ")).to eq(false)
      expect(u.valid_password?("I love to eat apples and bananas!")).to eq(false)
      expect(u.valid_password?("I love to eat apples and banana")).to eq(false)
      expect(GoSecure).to receive(:matches_password?).with("hippopotamus", pw)
      u.valid_password?("hippopotamus")
    end
    
    it "should validate an outdated password" do
      u = User.new
      u.settings = {}
      salt = Digest::MD5.hexdigest("pw" + Time.now.to_i.to_s)
      hash = Digest::SHA512.hexdigest(GoSecure.encryption_key + salt + "bacon")
      u.settings['password'] = {
        'hash_type' => 'sha512',
        'hashed_password' => hash,
        'salt' => salt
      }
      expect(GoSecure.outdated_password?(u.settings['password'])).to eq(true)
      expect(u.valid_password?('bracken')).to eq(false)
      expect(u.valid_password?('bacon')).to eq(true)
    end
    
    it "should re-generate an outdated password" do
      u = User.new
      u.settings = {}
      salt = Digest::MD5.hexdigest("pw" + (Time.now.to_i - 10).to_s)
      hash = Digest::SHA512.hexdigest(GoSecure.encryption_key + salt + "bacon")
      u.settings['password'] = {
        'hash_type' => 'sha512',
        'hashed_password' => hash,
        'salt' => salt
      }
      expect(GoSecure.outdated_password?(u.settings['password'])).to eq(true)
      expect(u.valid_password?('bacon')).to eq(true)
      expect(u.settings['password']['hash_type']).to eq('pbkdf2-sha256')
      expect(u.settings['password']['hashed_password']).not_to eq(hash)
      expect(u.settings['password']['salt']).not_to eq(salt)
    end
    
    it "should not re-generate an outdated password on a bad guess" do
      u = User.new
      u.settings = {}
      salt = Digest::MD5.hexdigest("pw" + Time.now.to_i.to_s)
      hash = Digest::SHA512.hexdigest(GoSecure.encryption_key + salt + "bacon")
      u.settings['password'] = {
        'hash_type' => 'sha512',
        'hashed_password' => hash,
        'salt' => salt
      }
      expect(GoSecure.outdated_password?(u.settings['password'])).to eq(true)
      expect(u.valid_password?('baconator')).to eq(false)
      expect(u.settings['password']['hash_type']).to eq('sha512')
      expect(u.settings['password']['hashed_password']).to eq(hash)
      expect(u.settings['password']['salt']).to eq(salt)
    end
  end
end
