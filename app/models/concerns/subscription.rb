module Subscription
  extend ActiveSupport::Concern
  
  def update_subscription_organization(org_id, pending=false, sponsored=true)
    # used to pause subscription when the user is adopted by an organization, 
    # and possibly to resume the subscription when the user is dropped by an organization.
    prior_org = self.managing_organization
    actual_id = nil
    if org_id
      new_org = Organization.find_by_global_id(org_id)
      actual_id = new_org && new_org.id
      self.settings['subscription'] ||= {}
      if sponsored
        self.settings['subscription']['started'] = nil
        if self.expires_at && self.expires_at > Time.now
          self.settings['subscription']['seconds_left'] = self.expires_at.to_i - Time.now.to_i
          self.expires_at = nil
        end
      end
      self.settings['subscription']['org_sponsored'] = sponsored
      self.settings['subscription']['added_to_organization'] = Time.now.iso8601
      self.settings['subscription']['org_pending'] = pending || false
      self.settings['preferences'] ||= {}
      self.settings['preferences']['role'] = 'communicator'
      if new_org
        Organization.detach_user(self, 'user', new_org)
        new_org.attach_user(self, 'user', {'approved_user' => !pending, 'sponsored_user' => sponsored)
        self.settings['managed_by'] = {}
        self.settings['managed_by'][new_org.global_id] = {
          'added' => Time.now.iso8601,
          'sponsored' => sponsored,
          'pending' => pending
        }
        if sponsored && !pending
          self.schedule(:process_subscription_token, 'token', 'unsubscribe')
        end
      end
      if !prior_org || prior_org != new_org
        UserMailer.schedule_delivery(:organization_assigned, self.global_id, new_org && new_org.global_id)
      end
    else
      self.settings['subscription'] ||= {}
      self.settings['subscription']['started'] = nil
      self.settings['subscription']['added_to_organization'] = nil
      Organization.detach_user(self, 'user')
      self.settings['managed_by'] = nil
      if self.settings['subscription']['org_sponsored']
        self.settings['subscription']['org_sponsored'] = nil
        if self.settings['subscription']['seconds_left']
          self.expires_at = Time.now + self.settings['subscription']['seconds_left']
          self.settings['subscription'].delete('seconds_left')
        end
        self.expires_at = [self.expires_at, 2.weeks.from_now].compact.max
      end
      # self.schedule(:update_subscription, {'resume' => true})
      if prior_org
        UserMailer.schedule_delivery(:organization_unassigned, self.global_id, prior_org && prior_org.global_id)
      end
    end
    self.managing_organization_id = actual_id
    self.save
  end
  
  def transfer_subscription_to(user, skip_remote_update=false)
    transfer_keys = ['started', 'plan_id', 'subscription_id', 'token_summary', 'free_premium', 
      'never_expires', 'seconds_left', 'customer_id']
    did_change = false
    transfer_keys.each do |key|
      self.settings['subscription'] ||= {}
      user.settings['subscription'] ||= {}
      if self.settings['subscription'][key] != nil
        did_change = true if ['subscription_id', 'customer_id'].include?(key)
        user.settings['subscription'][key] = self.settings['subscription'][key]
        self.settings['subscription'].delete(key)
      end
    end
    if did_change && !skip_remote_update
      Purchasing.change_user_id(user.settings['subscription']['customer_id'], self.global_id, user.global_id)
    end
    user.settings['subscription']['transferred_from'] ||= []
    user.settings['subscription']['transferred_from'] << self.global_id
    user.save
    self.settings['subscription']['transferred_to'] ||= []
    self.settings['subscription']['transferred_to'] << user.global_id
    self.save
  end
  
  def update_subscription(args)
    res = true
    self.settings['subscription'] ||= {}
    if args['subscribe']
      if !args['subscription_id'] || self.settings['subscription']['subscription_id'] == args['subscription_id']
        res = false
        # Not sure why changing customer_id should cause it to fail..
#       elsif self.settings['subscription']['customer_id'] && self.settings['subscription']['customer_id'] != args['customer_id']
#         res = false
      else
        role = (args['plan_id'] && args['plan_id'].match(/^slp/)) ? 'supporter' : 'communicator'
        self.settings['subscription']['subscription_id'] = args['subscription_id']
        if args['customer_id']
          if self.settings['subscription']['customer_id'] && self.settings['subscription']['customer_id'] != args['customer_id']
            self.settings['subscription']['prior_customer_ids'] ||= []
            self.settings['subscription']['prior_customer_ids'] << self.settings['subscription']['customer_id']
          end
          self.settings['subscription']['customer_id'] = args['customer_id']
        end
        self.settings['subscription']['started'] = Time.now.iso8601
        self.settings['subscription']['token_summary'] = args['token_summary']
        self.settings['subscription']['plan_id'] = args['plan_id']
        self.settings['subscription']['free_premium'] = args['plan_id'] == 'slp_monthly_free'
        self.settings['subscription'].delete('never_expires')
        self.settings['preferences']['role'] = role
        if self.expires_at && self.expires_at > Time.now
          self.settings['subscription']['seconds_left'] = self.expires_at.to_i - Time.now.to_i
        end
        self.expires_at = nil
        self.save
      end
    elsif args['unsubscribe']
      if self.settings['subscription']['subscription_id'] == args['subscription_id'] || args['subscription_id'] == 'all'
        if self.settings['subscription']['seconds_left']
          self.expires_at = Time.now + self.settings['subscription']['seconds_left']
          self.settings['subscription'].delete('seconds_left')
        end
        self.expires_at = [self.expires_at, 2.weeks.from_now].compact.max
        self.settings['subscription'].delete('subscription_id')     
        self.settings['subscription'].delete('token_summary')     
        self.settings['subscription'].delete('started')     
        self.settings['subscription'].delete('plan_id')     
        self.settings['subscription'].delete('free_pemium')
        self.settings['subscription'].delete('never_expires')
        self.save
      else
        res = false
      end
    elsif args['purchase']
      if true
        self.settings['subscription'].delete('started')
        if args['customer_id']
          if self.settings['subscription']['customer_id'] && self.settings['subscription']['customer_id'] != args['customer_id']
            self.settings['subscription']['prior_customer_ids'] ||= []
            self.settings['subscription']['prior_customer_ids'] << self.settings['subscription']['customer_id']
          end
          self.settings['subscription']['customer_id'] = args['customer_id']
        end
        if args['gift_id']
          self.settings['subscription']['gift_ids'] ||= []
          self.settings['subscription']['gift_ids'] << args['gift_id']
        end
        self.settings['subscription']['token_summary'] = args['token_summary']
        self.settings['subscription']['last_purchase_plan_id'] = args['plan_id']
        self.settings['subscription']['free_premium'] = args['plan_id'] == 'slp_long_term_free'
        self.settings['subscription'].delete('never_expires')
        self.settings['subscription']['prior_purchase_ids'] ||= []
        if self.settings['subscription']['prior_purchase_ids'].include?(args['purchase_id'])
          res = false
        else
          role = (args['plan_id'] && args['plan_id'].match(/^slp/)) ? 'supporter' : 'communicator'
          self.settings['subscription']['prior_purchase_ids'] << args['purchase_id']
          self.settings['preferences']['role'] = role
          self.expires_at = [self.expires_at, Time.now].compact.max
          self.expires_at += args['seconds_to_add']
        end
      
        self.save
      end
    elsif args['pause']
      # TODO: no such thing, just have to cancel and then re-instate
      # TODO: add confirmation step before subscription is cancelled when added to an org
      if self.settings['subscription']['started']
        res = Purchasing.pause_subscription(self)
        if res[:success]
          self.settings['subscription']['started'] = nil
          self.save
        elsif args['attempts'] && args['attempts'] > 5
          SubscriptionMailer.schedule_delivery(:subscription_pause_failed, self.global_id)
        else
          args['attempts'] ||= 0
          args['attempts'] += 1
          self.schedule(:update_subscription, args)
        end
      end
    elsif args['resume']
      res = Purchasing.resume_subscription(self)
      if res[:success]
        self.settings['subscription']['started'] = Time.now.iso8601
        self.save
      elsif args['attempts'] && args['attempts'] > 5
        SubscriptionMailer.schedule_delivery(:subscription_resume_failed, self.global_id)
      else
        args['attempts'] ||= 0
        args['attempts'] += 1
        self.schedule(:update_subscription, args)
      end
    else
      res = false
    end
    res
  end
  
  def redeem_gift_token(code)
    Purchasing.redeem_gift(code, self)
  end
  
  def process_subscription_token(token, type)
    if type == 'unsubscribe'
      Purchasing.unsubscribe(self)
    else
      Purchasing.purchase(self, token, type)
    end
  end
  
  def subscription_override(type, user_id=nil)
    if type == 'never_expires'
      self.process({}, {'premium_until' => 'forever'})
    elsif type == 'eval'
      self.update_subscription({
        'subscribe' => true,
        'subscription_id' => 'free_eval',
        'token_summary' => "Manually-set Eval Account",
        'plan_id' => 'eval_monthly_free'
      })
    elsif type == 'add_1'
      if self.expires_at
        self.expires_at = [self.expires_at, Time.now].max + 1.month
        self.settings ||= {}
        self.settings['subscription_adders'] ||= []
        self.settings['subscription_adders'] << [user_id, Time.now.to_i]
        self.save
      end
    elsif type == 'manual_supporter'
      self.update_subscription({
        'subscribe' => true,
        'subscription_id' => 'free',
        'token_summary' => "Manually-set Supporter Account",
        'plan_id' => 'slp_monthly_free'
      })
    else
      false
    end
  end
  
  def subscription_event(args)
    if args['purchase_failed']
      SubscriptionMailer.schedule_delivery(:purchase_bounced, self.global_id)
      return true
    elsif args['purchase']
      is_new = update_subscription(args)
      if is_new
        if args['plan_id'] == 'gift_code'
          SubscriptionMailer.schedule_delivery(:gift_redeemed, args['gift_id'])
          SubscriptionMailer.schedule_delivery(:gift_seconds_added, args['gift_id'])
        else
          SubscriptionMailer.schedule_delivery(:purchase_confirmed, self.global_id)
        end
      end
      return is_new
    elsif args['subscribe']
      is_new = update_subscription(args)
      SubscriptionMailer.schedule_delivery(:purchase_confirmed, self.global_id) if is_new
      return is_new
    elsif args['unsubscribe']
      is_new = update_subscription(args)
      SubscriptionMailer.schedule_delivery(:subscription_expiring, self.global_id) if is_new
      return is_new
    elsif args['chargeback_created']
      SubscriptionMailer.schedule_delivery(:chargeback_created, self.global_id)
      return true
    end
    true
  end
  
  def premium?
    !!(never_expires? || self.recurring_subscription? || self.org_sponsored? || (self.expires_at && self.expires_at > Time.now) || self.free_premium?)
  end
  
  def org_sponsored?
    Organization.sponsored?(self)
  end
  
  def free_premium?
    !!(self.settings && self.settings['subscription'] && self.settings['subscription']['free_premium'])
  end
  
  def never_expires?
    !!(self.settings && self.settings['subscription'] && self.settings['subscription']['never_expires'])
  end

  def grace_period?
    !!(self.expires_at && self.expires_at > Time.now && !self.org_sponsored? && !self.never_expires? && !self.long_term_purchase? && !self.recurring_subscription?)
  end
  
  def long_term_purchase?
    !!(!self.never_expires? && self.expires_at && self.expires_at > Time.now && self.settings && self.settings['subscription'] && self.settings['subscription']['last_purchase_plan_id'])
  end
  
  def recurring_subscription?
    !!(self.settings && self.settings['subscription'] && self.settings['subscription']['started'])
  end
  
  def subscription_hash
    json = {}
    self.settings['subscription'] ||= {}
    if self.never_expires?
      json['never_expires'] = true
      json['active'] = true
    elsif self.org_sponsored?
      json['active'] = true
    else
      json['expires'] = self.expires_at && self.expires_at.iso8601
      json['grace_period'] = self.grace_period?
      if self.recurring_subscription?
        json['active'] = true
        json['started'] = self.settings['subscription']['started']
        json['plan_id'] = self.settings['subscription']['plan_id']
        json['free_premium'] = self.settings['subscription']['free_premium'] if self.free_premium?
      elsif self.long_term_purchase?
        json['active'] = true
        json['purchased'] = self.settings['subscription']['customer_id'] != 'free'
        json['plan_id'] = self.settings['subscription']['last_purchase_plan_id']
        json['free_premium'] = self.settings['subscription']['free_premium'] if self.free_premium?
      end
    end
    # TODO: remove in later API revision, after like July 2016
    if Organization.managed?(self)
      json['is_managed'] = true
      org = self.managing_organization
      json['org_pending'] = org.pending_user?(self)
      json['org_sponsored'] = org.sponsored_user?(self)
      json['managing_org_name'] = (org && org.settings['name']) || "unknown organization"
      json['added_to_organization'] = self.settings['subscription']['added_to_organization'] if self.settings['subscription']['added_to_organization']
    end
    json
  end
  
  def log_subscription_event(hash)
    self.settings ||= {}
    hash[:time] = Time.now.to_i
    self.settings['subscription_events'] ||= []
    self.settings['subscription_events'] << hash
    self.save
  end
      
  module ClassMethods  
    def check_for_subscription_updates
      # TODO: send out a one-month and three-month warning for long-term purchase subscriptions
      alerts = {:approaching => 0, :approaching_emailed => 0, :upcoming => 0, :upcoming_emailed => 0, :expired => 0, :expired_emailed => 0, :recent_less_active => 0}
      
      [1, 3].each do |num|
        approaching_expires = User.where(['expires_at > ? AND expires_at < ?', num.months.from_now - 0.5.days, num.months.from_now + 0.5.days])
        approaching_expires.each do |user|
          if !user.grace_period? && user.premium?
            alerts[:approaching] += 1
            user.settings['subscription'] ||= {}
            last_message = Time.parse(user.settings['subscription']['last_approaching_notification']) rescue Time.at(0)
            if last_message < 1.week.ago
              SubscriptionMailer.deliver_message(:expiration_approaching, user.global_id)
              user.settings['subscription']['last_approaching_notification'] = Time.now.iso8601
              user.save
              alerts[:approaching_emailed] += 1
            end
          end
        end
      end
      
      upcoming_expires = User.where(['expires_at > ? AND expires_at < ?', 6.hours.from_now, 1.week.from_now])
      # send out a warning notification 1 week before, and another one the day before,
      # to all the ones that haven't been warned yet for this cycle
      upcoming_expires.each do |user|
        alerts[:upcoming] += 1
        user.settings['subscription'] ||= {}
        last_day = Time.parse(user.settings['subscription']['last_expiring_day_notification']) rescue Time.at(0)
        last_week = Time.parse(user.settings['subscription']['last_expiring_week_notification']) rescue Time.at(0)
        if user.expires_at <= 36.hours.from_now && last_day < 1.week.ago
          SubscriptionMailer.deliver_message(:one_day_until_expiration, user.global_id)
          user.settings['subscription']['last_expiring_day_notification'] = Time.now.iso8601
          user.save
          alerts[:upcoming_emailed] += 1
        elsif user.expires_at > 4.days.from_now && last_week < 1.week.ago
          SubscriptionMailer.deliver_message(:one_week_until_expiration, user.global_id)
          user.settings['subscription']['last_expiring_week_notification'] = Time.now.iso8601
          user.save
          alerts[:upcoming_emailed] += 1
        end
      end
      
      now_expired = User.where(['expires_at > ? AND expires_at < ?', 3.days.ago, Time.now])
      # send out an expiration notification to all the ones that haven't been notified yet
      now_expired.each do |user|
        alerts[:expired] += 1
        user.settings['subscription'] ||= {}
        last_expired = Time.parse(user.settings['subscription']['last_expired_notification']) rescue Time.at(0)
        if user.expires_at < Time.now && last_expired < 3.days.ago
          SubscriptionMailer.deliver_message(:subscription_expired, user.global_id)
          user.settings['subscription']['last_expired_notification'] = Time.now.iso8601
          user.save          
          alerts[:expired_emailed] += 1
        end
      end
      
      recently_registered = User.where(['created_at > ? AND created_at < ?', 10.days.ago, 5.days.ago])
      recent_but_less_active = recently_registered.select{|u| !u.settings['preferences']['logging'] || 
                                  u.devices.all?{|d| d.updated_at < 4.days.ago} || 
                                  !u.settings['preferences']['home_board'] || 
                                  (u.settings['preferences']['role'] == 'supporter' && u.supervised_user_ids.empty?)
                            }
      recent_but_less_active.each do |user|
        user.settings['subscription'] ||= {}
        last_reminded = Time.parse(user.settings['subscription']['last_logging_reminder_notification']) rescue Time.at(0)
        if last_reminded < 7.days.ago
          UserMailer.deliver_message(:usage_reminder, user.global_id)
          user.settings['subscription']['last_logging_reminder_notification'] = Time.now.iso8601
          user.save
          alerts[:recent_less_active] += 1
        end
      end
      alerts
    end
    
    def subscription_event(args)
      # ping from purchasing system, find the appropriate user and pass it along
      user = User.find_by_path(args['user_id'])
      return false unless user
      user.subscription_event(args)
    end
  end
end