class GiftPurchase < ActiveRecord::Base
  include Permissions
  include GlobalId
  include SecureSerialize
  include Processable
  secure_serialize :settings
  before_save :generate_defaults
  replicated_model  
  
  add_permissions('view', ['*']) { self.active == true }
  add_permissions('manage') {|user| Organization.admin_manager?(user) }
  add_permissions('manage') {|user| (self.settings['admin_user_ids'] || []).include?(user.global_id) }

  def self.find_by_code(code)
    code = (code || '').downcase.gsub(/o/, '0')
    parts = code.split(/x/)
    if parts.length > 1
      gifts = GiftPurchase.where(["code LIKE ?", "#{parts[0]}%"])
      gift = gifts.detect{|g| g.settings['total_codes'] && g.settings['codes'].has_key?(code) }
    else
      gift = GiftPurchase.where(:code => code, :active => true).first
    end
  end
  
  def generate_defaults
    self.settings ||= {}
    self.active = true if self.active == nil
    self.active = false if self.settings['purchase_id'] && self.settings['licenses']
    self.settings['code_length'] = 20 if self.settings['licenses']
    self.settings['code_length'] = 40 if self.settings['total_codes']
    if !self.code
      code = nil
      length = self.settings['code_length'] || 8
      while !code || GiftPurchase.where(:active => true, :code => code).count > 0
        code = (GoSecure.nonce('gift_code') + GoSecure.nonce('gift_code'))[0, length.floor]
        length += 0.5
      end
      self.code = code
      if self.settings['total_codes'] && !self.settings['codes']
        self.settings['codes'] = {}
        while self.settings['codes'].keys.length < self.settings['total_codes']
          code = "#{self.code[0, 4]}x#{GoSecure.nonce('gift_code_sub')[0, 4]}"
          self.settings['codes'][code] ||= nil
        end
      end
    end
    true
  end
  
  def gift_type
    if self.settings['total_codes']
      'multi_code'
    elsif self.settings['licenses']
      'bulk_purchase'
    else
      'user_gift'
    end
  end
  
  def notify_of_creation
    SubscriptionMailer.schedule_delivery(:gift_created, self.global_id)
    SubscriptionMailer.schedule_delivery(:gift_updated, self.global_id, 'purchase')
    true
  end
  
  def duration
    time = {}
    left = self.settings && self.settings['seconds_to_add']
    return "no time specified" unless left && left > 0
    units = [[1.year.to_i, 'year'], [1.day.to_i, 'day'], [1.hour.to_i, 'hour'], [1.minute.to_i, 'minute']]
    units.each do |seconds, unit|
      while left >= seconds
        time[unit] = (time[unit] || 0) + 1
        left -= seconds
      end
    end
    res = []
    units.each do |seconds, unit|
      if time[unit] && time[unit] > 0
        str = "#{time[unit]} #{unit}"
        str += "s" if time[unit] > 1
        res << str
      end
    end
    res.join(", ")
  end
  
  def receiver
    id = self.settings && self.settings['receiver_id']
    User.find_by_global_id(id)
  end
  
  def giver
    id = self.settings && self.settings['giver_id']
    User.find_by_global_id(id)
  end
  
  def bulk_purchase?
    !!(self.settings && self.settings['licenses'])
  end
  
  def purchased?
    !!(self.settings && self.settings['purchase_id'])
  end
  
  def process_params(params, non_user_params)
    self.settings ||= {}
    self.settings['giver_email'] = params['email'] if params['email']
    self.settings['giver_email'] = non_user_params['email'] if non_user_params['email']
    if non_user_params['giver']
      self.settings['giver_id'] = non_user_params['giver'].global_id
      self.settings['giver_email'] ||= non_user_params['giver'].settings['email'] if non_user_params['giver'].settings['email']
    end

    ['licenses', 'total_codes', 'amount', 'memo', 'email', 'organization', 'gift_name'].each do |arg|
      self.settings[arg] = params[arg] if params[arg] && !params[arg].blank?
    end
    if params['org_id']
      org = Organization.find_by_global_id(params['org_id'])
      self.settings['org_id'] = org.global_id
    end
    
    if non_user_params['giver'] && self.settings['licenses']
      self.settings['giver_email'] = non_user_params['giver'].settings['email'] if non_user_params['giver'].settings['email']
    end

    ['customer_id', 'token_summary', 'plan_id', 'purchase_id'].each do |arg|
      self.settings[arg] = non_user_params[arg] if non_user_params[arg]
    end
    self.settings['seconds_to_add'] = non_user_params['seconds'].to_i if non_user_params['seconds']
  end
  
  def self.process_subscription_token(token, opts)
    Purchasing.purchase_gift(token, opts)
  end
  
#  def self.redeem(code, user)
#    Purchasing.redeem_gift(code, user)
#  end
  
  def redeem_code!(code, user)
    if self.gift_type == 'multi_code'
      parts = code.split(/x/)
      raise "invalid code" unless self.code[0, 4] == parts[0] && self.settings['codes'].has_key?(code)
      raise "code already redeemed" if !self.active || self.settings['codes'][code] != nil
      self.settings['codes'][code] = {
        'redeemed_at' => Time.now.iso8601,
        'receiver_id' => user.global_id
      }
      self.active = false if self.settings['codes'].to_a.map(&:last).all?{|v| v != nil }
    elsif self.gift_type == 'user_gift'
      raise "invalid code" unless self.code == code
      self.active = false
      self.settings['receiver_id'] = user.global_id
      self.settings['redeemed_at'] = Time.now.iso8601
    else
      raise "invalid code"
    end
    if self.settings['org_id']
      org = Organization.find_by_global_id(self.settings['org_id'])
      org.add_user(user.global_id, false, false, false)
    end
    self.save
  end
end
