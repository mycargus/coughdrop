module Passwords
  extend ActiveSupport::Concern
  
  def generate_password_reset
    clean_password_resets
    if self.settings['password_resets'].length > 5
      Rails.logger.warn("Throttled password reset for user \"#{self.user_name}\", too many attempts")
      return false 
    end
    self.settings['password_resets'] << {
      'timestamp' => Time.now.to_i,
      'code' => GoSecure.nonce('password_reset_code')
    }
    self.save
  end
  
  def password_reset_code
    clean_password_resets
    reset = self.settings['password_resets'][-1]
    reset && reset['code']
  end
  
  def reset_token_for_code(code)
    clean_password_resets
    reset = self.settings['password_resets'].detect{|r| r['code'] == code }
    return nil unless reset
    
    reset['token'] = GoSecure.nonce('password_reset_token')
    self.save
    reset['token']
  end
  
  def valid_reset_token?(token)
    clean_password_resets
    !!self.settings['password_resets'].detect{|r| r['token'] == token }
  end
  
  def used_reset_token!(token)
    clean_password_resets
    self.settings['password_resets'] = self.settings['password_resets'].select{|r| r['token'] != token }
    self.save
  end
  
  def clean_password_resets
    self.settings ||= {}
    now = Time.now.to_i
    self.settings['password_resets'] ||= []
    self.settings['password_resets'].select!{|r| r['timestamp'] > now - (60 * 60 * 3) }
  end

  def valid_password?(guess)
    self.settings ||= {}
    res = GoSecure.matches_password?(guess, self.settings['password'])
    if res && GoSecure.outdated_password?(self.settings['password'])
      self.generate_password(guess)
      self.save
    end
    res
  end
  
  def generate_password(password)
    self.settings ||= {}
    self.settings['password'] = GoSecure.generate_password(password)
  end
end