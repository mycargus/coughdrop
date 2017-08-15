class Device < ActiveRecord::Base
  include GlobalId
  include SecureSerialize
  secure_serialize :settings
  belongs_to :user
  belongs_to :developer_key
  belongs_to :user_integration
  before_save :generate_defaults
  after_save :update_user_device_name

  def generate_defaults
    self.settings ||= {}
    self.settings['name'] ||= 'Web browser for Desktop' if self.default_device?
    self.settings['name'] ||= self.device_key.split(/\s/, 2)[1] if self.system_generated?
    true
  end
  
  def system_generated?
    self.developer_key_id == 0
  end
  
  def default_device?
    self.device_key == 'default' && self.system_generated?
  end
  
  def hidden?
    !!self.settings['hidden']
  end
  
  def disabled?
    !!(self.settings && self.settings['disabled'])
  end
  
  def permission_scopes
    if disabled?
      []
    elsif self.user_integration_id
      (self.settings && self.settings['permission_scopes']) || []
    elsif self.developer_key_id && self.developer_key_id != 0
      (self.settings && self.settings['permission_scopes']) || []
    else
      ['full']
    end
  end
  
  def last_used_at
    uses = (self.settings['keys'] || []).map{|k| k['last_timestamp'] }.sort
    time = uses.length > 0 && Time.at(uses.last) rescue nil
    time ||= self.created_at
  end
  
  def update_user_device_name
    # if the device_name changed the it'll need to be updated on the user record
  end
  
  def generate_token!(force_long_token=false)
    raise "device must already be saved" unless self.id
    clean_old_keys
    # TODO: this check should probably be based on developer key whenever we do that part
    if !self.system_generated?
      # browsers are different than devices in that they can have multiple tokens for the same device
      self.settings['keys'] = []
    end
    key = "#{self.global_id}~#{Digest::SHA512.hexdigest(Time.now.to_i.to_s + rand(99999).to_s + self.global_id)}"
    
    # Keep track of which devices were used most recently/frequently to help
    # display most-relevant ones in the UI under "user devices".
    self.settings['token_history'] ||= []
    self.settings['token_history'] << Time.now.to_i
    self.settings['keys'] << {
      'value' => key,
      'timestamp' => Time.now.to_i,
      'last_timestamp' => Time.now.to_i,
      'timeout' => self.inactivity_timeout(force_long_token)
    }
    self.save
  end
  
  def logout!
    self.settings['keys'] = []
    self.save
  end
  
  def unique_device_key
    raise "must be saved first" unless self.global_id
    return device_key if self.system_generated?
    raise "missing developer_key_id" unless self.developer_key_id
    "#{self.device_key}_#{self.developer_key_id}"
  end
  
  def inactivity_timeout(force_long_timeout=false)
    if self.user_integration_id
      6.months.to_i
    elsif force_long_timeout
      28.days.to_i
    else
      24.hours.to_i
    end
  end
  
  def invalidate_keys!
    self.settings ||= {}
    self.settings['keys'] = []
    self.save
  end
  
  def clean_old_keys
    self.settings ||= {}
    keys = self.settings['keys'] || []
    keys = keys.select{|k| k['last_timestamp'] > Time.now.to_i - (k['timeout'] || self.inactivity_timeout) }
    self.settings['keys'] = keys
  end
  
  def valid_token?(token, app_version=nil)
    clean_old_keys
    return false if self.disabled?
    keys = (self.settings && self.settings['keys']) || []
    key = keys.detect{|k| k['value'] == token }
    do_save = false
    if key && key['last_timestamp'] < 30.minutes.ago.to_i
      self.settings['keys'].each_with_index do |key, idx|
        if key['value'] == token
          key['last_timestamp'] = Time.now.to_i
          self.settings['keys'][idx] = key
          do_save = true
        end
      end
    end
    if app_version && self.settings['app_version'] != app_version
      self.settings['app_version'] = app_version
      self.settings['app_versions'] ||= []
      self.settings['app_versions'] << [app_version, Time.now.to_i]
      self.settings['app_versions'] = self.settings['app_versions'].uniq(&:first)
      do_save = true
    end
    self.save if do_save
    !!key
  end
  
  def token
    clean_old_keys
    if self.settings['keys'].empty?
      self.generate_token!
    end
    self.settings['keys'][-1]['value']
  end
end
