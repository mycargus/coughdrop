class UserIntegration < ActiveRecord::Base
  include Processable
  include Permissions
  include Async
  include GlobalId
  include SecureSerialize
  include Notifiable

  belongs_to :user
  belongs_to :device
  belongs_to :template_integration, :class_name => 'UserIntegration'
  before_save :generate_defaults
  after_save :assert_device
  after_save :assert_webhooks
  after_destroy :disable_device
  after_destroy :delete_webhooks
#  has_paper_trail :only => [:settings]
  secure_serialize :settings
  replicated_model
  
  add_permissions('view', ['*']) { self.settings['global'] || self.template }
  add_permissions('view', ['read_profile']) {|user| self.user_id == user.id }
  add_permissions('view', 'edit', 'delete') {|user| self.user_id == user.id }
  add_permissions('view', ['read_profile']) {|user| self.user && self.user.allows?(user, 'edit') }
  add_permissions('view', 'edit', 'delete') {|user| self.user && self.user.allows?(user, 'edit') }
  cache_permissions
  
  def generate_defaults
    self.settings ||= {}
    self.settings['token'] ||= self.class.security_token
    self.settings['static_token'] ||= self.class.security_token
    if self.template_integration && self.template_integration.integration_key
      self.settings['template_key'] = self.template_integration.integration_key
      self.settings['icon_url'] ||= self.template_integration.settings['icon_url']
      self.settings['name'] ||= self.template_integration.settings['name']
    end
    self.settings['permission_scopes'] ||= ['read_profile']
    if !self.settings['obfuscation_offset']
      hash = {}
      '0123456789'.each_char do |n|
        val = nil
        while !val || hash.to_a.map(&:last).include?(val)
          val = rand(99)
        end
        hash[n] = val
      end
      self.settings['obfuscation_offset'] = hash
    end
    self.for_button = !!(self.settings['button_webhook_url'] || self.settings['board_render_url'])
    self.assert_device
    # TODO: assert device
  end
  
  def self.security_token
    GoSecure.sha512('user integration security token', GoSecure.nonce('integration_nonce'))
  end
  
  def user_token(user)
    return nil unless user && user.global_id
    # user token must be consistent across repeated launches
    sig = self.class.user_token(user.global_id, self.global_id)
    if !self.settings['obfuscation_offset']
      self.generate_defaults
      self.save!
    end
    "#{self.class.obfuscate_user_id(user.global_id, self.settings['obfuscation_offset'])}:#{self.global_id}:#{sig}"
  end
  
  def self.obfuscate_user_id(user_id, lookup)
    raise "bad id" unless user_id.match(/^[_0123456789]+$/)
    shard, user_id = user_id.split(/_/)
    val = 0
    keys = {}
    user_id.each_char{|c| val = (val * 100) + lookup[c]}
    "#{shard}_#{val.to_s(16)}"
  end
  
  def self.deobfuscate_user_id(str, lookup)
    shard, str = str.split(/_/)
    val = str.hex
    res = ""
    while val > 0
      num = (val % 100)
      res = lookup.to_a.detect{|n, val| val == num }[0] + res
      val = val / 100
    end
    return nil unless res.match(/^[_0123456789]+$/)
    "#{shard}_#{res}"
  end
  
  def self.user_token(user_id, integration_id)
    sig = GoSecure.sha512("user_integration_confirmation_token_#{user_id}_#{integration_id}", 'user_integration_confirmation_token_nonce')
  end
  
  def assert_device
    if !self.device
      self.device = Device.create(:user => user)
    end
    if self.device && self.device.id && self.id
      self.device.user_integration_id = self.id
      self.device.settings['name'] = self.settings['name']
      self.device.settings['permission_scopes'] = self.settings['permission_scopes']
      self.device.save
    end
    if self.user
      self.user.update_setting('has_user_integrations', true)
    end
  end
  
  def assert_webhooks(frd=false)
    if @install_default_webhooks && !frd
      schedule(:assert_webhooks, true)
    elsif frd
      if for_button && self.settings['button_webhook_url']
        hook = nil
        if self.settings['button_webhook_id']
          hook = Webhook.find_by_path(self.settings['button_webhook_id'])
        else
          hook = Webhook.create(:user_integration_id => self.id)
          self.settings['button_webhook_id'] = hook.global_id
          self.save
        end
        if hook
          hook.settings['name'] = self.settings['name']
          hook.settings['notifications'] = {
            'button_action' => [{
              'callback' => self.settings['button_webhook_url'],
              'include_content' => true,
              'content_type' => 'button'
            }]
          }
          hook.record_code = self.record_code
          hook.user_id = self.user_id
          hook.save
        end
      end
      # install default webhooks
    end
    @install_default_webhooks = false
  end
  
  def process_params(params, non_user_params)
    raise "user required" unless self.user || non_user_params['user']
    self.user = non_user_params['user']

    self.settings ||= {}
    self.settings['name'] = process_string(params['name']) if params['name']
    self.settings['custom_integration'] = params['custom_integration'] if params['custom_integration'] != nil
    self.settings['button_webhook_url'] = params['button_webhook_url'] if params['button_webhook_url']
    self.settings['button_webhook_local'] = params['button_webhook_local'] if params['button_webhook_local']
    self.settings['board_render_url'] = params['board_render_url'] if params['board_render_url']
    self.settings['description'] = process_html(params['description']) if params['description']
    if params['integration_key']
      template = UserIntegration.find_by(template: true, integration_key: params['integration_key'])
      if !template
        add_processing_error('invalid template')
        return false
      end
      self.template_integration = template
      user_params = {}
      (template.settings['user_parameters'] || []).each do |template_param|
        user_param = (params['user_parameters'] || []).detect{|p| p['name'] == template_param['name']}
        if user_param
          user_params[template_param['name']] = {
            'type' => template_param['type'],
            'label' => template_param['label']
          }
          value = user_param['value']
          if template_param['type'] == 'password'
            if template_param['downcase']
              value = value.downcase
            end
            if template_param['hash'] == 'md5'
              value = Digest::MD5.hexdigest(value)
            end
            secret, salt = GoSecure.encrypt(value, 'integration_password')
            user_params[template_param['name']]['salt'] = salt
            user_params[template_param['name']]['value_crypt'] = secret
          else
            user_params[template_param['name']]['value'] = value
          end
        end
      end
      self.settings['user_settings'] = user_params
      if params['integration_key'] == 'lessonpix' && user_params['username']
        identifiers = ['username']
        self.unique_key = GoSecure.sha512(user_params['username']['value'], "#{params['integration_key']}-#{identifiers.join('-')}")
        match = UserIntegration.find_by(unique_key: self.unique_key)
        if match && match.id != self.id
          add_processing_error('account credentials already in use')
          return false
        end
        res = Uploader.find_images('hat', 'lessonpix', self)
        if res == false
          add_processing_error('invalid user credentials')
          return false
        end
      end
    end
    # list of known types, probably need a background job here to confirm any
    # credentials that are provided
    @install_default_webhooks = true
    if params['regenerate_token']
      self.settings['token'] = self.class.security_token
    end
  end
  
  def delete_webhooks
    Webhook.where(:user_integration_id => self.id).each{|h| h.destroy }
    true
  end
  
  def disable_device
    d = self.device
    if d
      d.settings['disabled'] = true
      d.save
    end
    true
  end
  
  def allow_private_information?
    false
  end
  
  def placement_code(*args)
    raise "needs at least one arg" unless args.length > 0
    raise "strings only" if args.any?{|a| !a.is_a?(String) }
    args << self.settings['static_token']
    GoSecure.sha512(args.join(","), 'user integration placement code')
  end
  
  def self.integration_keys_for(user)
    return [] unless user
    # TODO: sharding
    UserIntegration.where(user_id: user.id).map(&:integration_key).compact.uniq
  end
  
  def self.global_integrations
    expires ||= 30.minutes.to_i

    cache_key = "global_integrations"
    cached_val = RedisInit.permissions && RedisInit.permissions.get(cache_key)
    return JSON.parse(cached_val) if cached_val
    
    res = {}
    UserIntegration.where('integration_key IS NOT NULL').each do |ui|
      res[ui.integration_key] = ui.global_id if ui.settings['global']
    end
    
    if RedisInit.permissions
      RedisInit.permissions.setex(cache_key, expires, res.to_json)
    end
    res
  end
end
