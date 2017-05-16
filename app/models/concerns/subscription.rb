module Subscription
  extend ActiveSupport::Concern
  
  def clear_existing_subscription(opts={})
    opts = opts || {}
    self.settings['subscription'] ||= {}

    if opts[:track_seconds_left]
      if self.expires_at && self.expires_at > Time.now
        self.settings['subscription']['seconds_left'] = [(self.settings['subscription']['seconds_left'] || 0), (self.expires_at.to_i - Time.now.to_i)].max
      end
      self.expires_at = nil
    else
      if self.settings['subscription']['seconds_left']
        self.expires_at = [self.expires_at, Time.now + self.settings['subscription']['seconds_left']].compact.max
        self.settings['subscription'].delete('seconds_left')
      end
    end
    
    if self.recurring_subscription?
      started = Time.parse(self.settings['subscription']['started']) rescue nil
      if started
        self.settings['past_purchase_durations'] ||= []
        self.settings['past_purchase_durations'] << {type: 'recurring', started: self.settings['subscription']['started'], duration: (Time.now.to_i - started.to_i)}
      end
      ['subscription_id', 'token_summary', 'started', 'plan_id', 'free_premium', 'never_expires'].each do |key|
        self.settings['subscription']['canceled'] ||= {}
        self.settings['subscription']['canceled'][key] = self.settings['subscription'][key]
      end
    end
    ['subscription_id', 'token_summary', 'started', 'plan_id', 'free_premium', 'never_expires'].each do |key|
      self.settings['subscription'].delete(key)
    end

    self.settings['subscription'].delete('started')
    self.settings['subscription'].delete('never_expires')
    self.settings['subscription'].delete('added_to_organization')
    if self.settings['managed_by']
      self.settings['past_purchase_durations'] ||= []
      self.settings['managed_by'].each do |id, opts|
        added = (opts['added'] && Time.parse(opts['added'])) rescue nil
        if added
          self.settings['past_purchase_durations'] << {type: 'org', started: opts['added'], duration: (Time.now.to_i - added.to_i)}
        end
      end
    end
    self.settings['managed_by'] = nil
    
    extra_expiration = opts[:allow_grace_period] ? 2.weeks.from_now : self.expires_at
    
    if self.settings['subscription']['org_sponsored']
      self.settings['subscription']['org_sponsored'] = nil
    end

    self.expires_at = [self.expires_at, extra_expiration].compact.max

    if self.settings['subscription']['last_purchase_id'] && !self.settings['subscription']['last_purchase_plan_id'].match(/free/)
      purchased = Time.parse(self.settings['subscription']['last_purchased']) rescue nil
      if purchased
        self.settings['past_purchase_durations'] ||= []
        self.settings['past_purchase_durations'] << {type: 'long_term', started: self.settings['subscription']['last_purchased'], duration: (Time.now.to_i - purchased.to_i)}
      end
      self.settings['subscription']['prior_purchase_ids'] << self.settings['subscription']['last_purchase_id']
      self.settings['subscription'].delete('last_purchase_id')
    end
    true
  end
  
  def update_subscription_organization(org_id, pending=false, sponsored=true)
    # used to pause subscription when the user is adopted by an organization, 
    # and possibly to resume the subscription when the user is dropped by an organization.
    prior_org = self.managing_organization
    if org_id
      new_org = org_id.is_a?(Organization) ? org_id : Organization.find_by_global_id(org_id)
      if new_org && self.settings['authored_organization_id'] == new_org.global_id && self.created_at > 2.weeks.ago
        pending = false
      end
      self.settings['subscription'] ||= {}
      if new_org
        Organization.detach_user(self, 'user', new_org)
      end
      if sponsored
        self.clear_existing_subscription(:track_seconds_left => true)
      end
      self.settings['subscription']['org_sponsored'] = sponsored
      self.settings['subscription']['added_to_organization'] = Time.now.iso8601
      self.settings['subscription']['org_pending'] = pending || false
      self.settings['preferences'] ||= {}
      self.settings['preferences']['role'] = 'communicator'
      self.settings['pending'] = false
      if new_org
        new_org.attach_user(self, 'user', {'approved_user' => !pending, 'sponsored_user' => sponsored})
        self.settings['managed_by'] = {}
        # if already there and not pending, don't re-set to pending
        if self.settings['managed_by'][new_org.global_id] && !self.settings['managed_by'][new_org.global_id]['pending']
          pending = false
        end
        self.settings['managed_by'][new_org.global_id] = {
          'added' => Time.now.iso8601,
          'sponsored' => sponsored,
          'pending' => pending
        }
        if sponsored && !pending
          self.expires_at = nil
          self.schedule(:process_subscription_token, 'token', 'unsubscribe')
        end
      end
      if !prior_org || prior_org != new_org
        UserMailer.schedule_delivery(:organization_assigned, self.global_id, new_org && new_org.global_id)
      end
    else
      self.settings['subscription'] ||= {}
      Organization.detach_user(self, 'user')
      self.clear_existing_subscription(:allow_grace_period => true) if self.org_sponsored?
      # self.schedule(:update_subscription, {'resume' => true})
      if prior_org
        UserMailer.schedule_delivery(:organization_unassigned, self.global_id, prior_org && prior_org.global_id)
      end
    end
    self.assert_current_record!
    self.save
  rescue ActiveRecord::StaleObjectError
    self.schedule(:update_subscription_organization, org_id, pending, sponsored)
  end
  
  def transfer_subscription_to(user, skip_remote_update=false)
    transfer_keys = ['started', 'plan_id', 'subscription_id', 'token_summary', 'free_premium', 
      'never_expires', 'seconds_left', 'customer_id', 'last_purchase_plan_id']
    did_change = false
    transfer_keys.each do |key|
      self.settings['subscription'] ||= {}
      user.settings['subscription'] ||= {}
      if self.settings['subscription'][key] != nil || user.settings['subscription'][key] != nil
        did_change = true if ['subscription_id', 'customer_id'].include?(key)
        user.settings['subscription'][key] = self.settings['subscription'][key]
        self.settings['subscription'].delete(key)
      end
    end
    if did_change && !skip_remote_update
      Purchasing.change_user_id(user.settings['subscription']['customer_id'], self.global_id, user.global_id)
    end
    from_list = (user.settings['subscription']['transferred_from'] || []) + [self.global_id]
    user.update_setting({
      'subscription' => {'transferred_from' => from_list}
    })
    to_list = (self.settings['subscription']['transferred_to'] || []) + [user.global_id]
    self.update_setting({
      'subscription' => {'transferred_to' => to_list}
    })
  end
  
  def update_subscription(args)
    res = true
    self.settings['subscription'] ||= {}
    if args['subscribe']
      if !args['subscription_id'] || self.settings['subscription']['subscription_id'] == args['subscription_id']
        res = false
      else
        role = (args['plan_id'] && args['plan_id'].match(/^slp/)) ? 'supporter' : 'communicator'
        self.settings['subscription']['prior_subscription_ids'] ||= []
        if self.settings['subscription']['prior_subscription_ids'].include?(args['subscription_id'])
          res = false
        else
          self.clear_existing_subscription(:track_seconds_left => true)
          self.settings['subscription']['subscription_id'] = args['subscription_id']
          if self.settings['subscription']['subscription_id'] && !self.settings['subscription']['subscription_id'].match(/free/)
            self.settings['subscription']['prior_subscription_ids'] << self.settings['subscription']['subscription_id']
          end
          if args['customer_id']
            if self.settings['subscription']['customer_id'] && self.settings['subscription']['customer_id'] != args['customer_id']
              self.settings['subscription']['prior_customer_ids'] ||= []
              self.settings['subscription']['prior_customer_ids'] << self.settings['subscription']['customer_id']
            end
            self.settings['subscription']['customer_id'] = args['customer_id']
          end
          self.settings['subscription']['started'] = Time.now.iso8601 
          self.settings['subscription']['started'] = nil if args['plan_id'] == 'monthly_free'
          self.settings['subscription']['token_summary'] = args['token_summary']
          self.settings['subscription']['plan_id'] = args['plan_id']
          self.settings['subscription']['free_premium'] = args['plan_id'] == 'slp_monthly_free'
          self.settings['preferences']['role'] = role
          self.settings['pending'] = false unless self.settings['subscription']['free_premium']
          self.settings['preferences']['progress'] ||= {}
          self.settings['preferences']['progress']['subscription_set'] = true
          self.expires_at = nil
          self.assert_current_record!
          self.save
          self.schedule(:remove_supervisors!) if self.free_premium?
        end
      end
    elsif args['unsubscribe']
      if (args['subscription_id'] && self.settings['subscription']['subscription_id'] == args['subscription_id']) || args['subscription_id'] == 'all'
        self.clear_existing_subscription(:allow_grace_period => true)
        self.settings['pending'] = false
        self.assert_current_record!
        self.save
      else
        res = false
      end
    elsif args['purchase']
      if args['purchase_id'] && self.settings['subscription']['last_purchase_id'] == args['purchase_id']
        res = false
      else
        self.settings['subscription']['prior_purchase_ids'] ||= []
        if args['purchase_id'] && self.settings['subscription']['prior_purchase_ids'].include?(args['purchase_id'])
          res = false
        else
          self.clear_existing_subscription
          if args['customer_id'] || args['customer_id'] == nil
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
          self.settings['subscription']['free_premium'] = (args['plan_id'] == 'slp_long_term_free')
          self.settings['pending'] = false unless self.settings['subscription']['free_premium']

          role = (args['plan_id'] && args['plan_id'].match(/^slp/)) ? 'supporter' : 'communicator'
          self.settings['subscription']['token_summary'] = args['token_summary']
          self.settings['subscription']['last_purchased'] = Time.now.iso8601
          self.settings['subscription']['last_purchase_plan_id'] = args['plan_id']
          self.settings['subscription']['last_purchase_id'] = args['purchase_id']
          self.settings['subscription']['last_purchase_seconds_added'] = args['seconds_to_add']
          self.settings['preferences']['role'] = role
          self.settings['preferences']['progress'] ||= {}
          self.settings['preferences']['progress']['subscription_set'] = true
          self.expires_at = [self.expires_at, Time.now].compact.max
          self.expires_at += args['seconds_to_add']
        end
      
        self.assert_current_record!
        self.save
      end
    else
      res = false
    end
    res
  rescue ActiveRecord::StaleObjectError
    return false
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
      self.process({}, {'pending' => false, 'premium_until' => 'forever'})
    elsif type == 'eval'
      self.update_subscription({
        'subscribe' => true,
        'subscription_id' => 'free_eval',
        'token_summary' => "Manually-set Eval Account",
        'plan_id' => 'eval_monthly_free'
      })
    elsif type == 'add_voice'
      self.allow_additional_premium_voice!
    elsif type == 'force_logout'
      self.devices.each{|d| d.invalidate_keys! }
      true
    elsif type == 'add_1' || type == 'communicator_trial'
      if type == 'communicator_trial'
        self.settings['preferences']['role'] = 'communicator'
        self.save
        self.update_subscription({
          'subscribe' => true,
          'subscription_id' => 'free_trial',
          'token_summary' => "Manually-set Communicator Account",
          'plan_id' => 'monthly_free'
        })
        self.expires_at ||= Time.now
      end
      if self.expires_at
        self.expires_at = [self.expires_at, Time.now].max + 1.month
        self.settings ||= {}
        self.settings['subscription_adders'] ||= []
        self.settings['subscription_adders'] << [user_id, Time.now.to_i]
        self.settings['pending'] = false
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
    self.log_subscription_event(:log => 'subscription event triggered remotely', :args => args)
    if args['purchase_failed']
      SubscriptionMailer.schedule_delivery(:purchase_bounced, self.global_id)
      return true
    elsif args['purchase']
      is_new = update_subscription(args)
      if is_new
        if args['plan_id'] == 'gift_code'
          SubscriptionMailer.schedule_delivery(:gift_redeemed, args['gift_id'])
          self.log_subscription_event(:log => 'gift notification triggered')
          SubscriptionMailer.schedule_delivery(:gift_seconds_added, args['gift_id'])
          SubscriptionMailer.schedule_delivery(:gift_updated, args['gift_id'], 'redeem')
        else
          SubscriptionMailer.schedule_delivery(:purchase_confirmed, self.global_id)
          self.log_subscription_event(:log => 'purchase notification triggered')
          SubscriptionMailer.schedule_delivery(:new_subscription, self.global_id)
        end
      end
      return is_new
    elsif args['subscribe']
      is_new = update_subscription(args)
      if is_new
        SubscriptionMailer.schedule_delivery(:purchase_confirmed, self.global_id) 
        self.log_subscription_event(:log => 'subscription notification triggered')
        SubscriptionMailer.schedule_delivery(:new_subscription, self.global_id) 
      end
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
  
  def supporter_role?
    self.settings && self.settings['preferences'] && self.settings['preferences']['role'] == 'supporter'
  end
  
  def communicator_role?
    !self.supporter_role?
  end
  
  def premium?
    !!(never_expires? || self.recurring_subscription? || self.org_sponsored? || (self.expires_at && self.expires_at > Time.now) || self.free_premium? || self.fully_purchased?)
  end

  def full_premium?
    !!(self.premium? && !self.free_premium? && !self.grace_period?)
  end
  
  def org_sponsored?
    Organization.sponsored?(self)
  end
  
  def fully_purchased?
    # long-term purchase, org-sponsored, or subscription for at least 2 years
    past_tally = (self.settings['past_purchase_durations'] || []).map{|d| d['duration'] || 0}.sum
    return true if past_tally > 2.years
    started = nil
    if self.settings['subscription'] && self.settings['subscription']['last_purchased'] && self.expires_at
      started = Time.parse(self.settings['subscription']['last_purchased']) rescue nil
    end
    if self.recurring_subscription?
      started = Time.parse(self.settings['subscription']['started']) rescue nil
    elsif self.org_sponsored?
      started = Time.parse(self.settings['managed_by'].map{|id, opts| opts['added'] }.compact.sort.first) rescue nil
    end
    if started
      return (past_tally + ([self.expires_at, Time.now].compact.max.to_i - started.to_i)) > 2.years
    else
      false
    end
  end
  
  def free_premium?
    if self.supporter_role? && self.expires_at && self.expires_at < Time.now && !self.long_term_purchase?
      self.schedule(:subscription_override, 'manual_supporter')
      return true
    end
    if self.expires_at && !self.long_term_purchase? && fully_purchased?
      return true
    end
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
#     if Organization.managed?(self)
#       json['is_managed'] = true
#       org = self.managing_organization
#       json['org_pending'] = org.pending_user?(self)
#       json['org_sponsored'] = org.sponsored_user?(self)
#       json['managing_org_name'] = (org && org.settings['name']) || "unknown organization"
#       json['added_to_organization'] = self.settings['subscription']['added_to_organization'] if self.settings['subscription']['added_to_organization']
#     end
    json
  end
  
  def log_subscription_event(hash)
    hash[:time] = Time.now.to_i
    AuditEvent.create({
      record_id: self.record_code,
      event_type: 'subscription_event',
      data: hash
    })
  end
  
  def subscription_events
    AuditEvent.where(event_type: 'subscription_event', record_id: self.record_code).order('id ASC').map{|e| e.data }
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
              user.update_setting({
                'subscription' => {'last_approaching_notification' => Time.now.iso8601}
              })
              alerts[:approaching_emailed] += 1
            end
          end
        end
      end
      
      upcoming_expires = User.where(['expires_at > ? AND expires_at < ?', 6.hours.from_now, 1.week.from_now])
      # send out a warning notification 1 week before, and another one the day before,
      # to all the ones that haven't been warned yet for this cycle
      upcoming_expires.each do |user|
        next unless user.communicator_role?
        alerts[:upcoming] += 1
        user.settings['subscription'] ||= {}
        last_day = Time.parse(user.settings['subscription']['last_expiring_day_notification']) rescue Time.at(0)
        last_week = Time.parse(user.settings['subscription']['last_expiring_week_notification']) rescue Time.at(0)
        if user.expires_at <= 36.hours.from_now && last_day < 1.week.ago
          SubscriptionMailer.deliver_message(:one_day_until_expiration, user.global_id)
          user.update_setting({
            'subscription' => {'last_expiring_day_notification' => Time.now.iso8601}
          })
          alerts[:upcoming_emailed] += 1
        elsif user.expires_at > 4.days.from_now && last_week < 1.week.ago
          SubscriptionMailer.deliver_message(:one_week_until_expiration, user.global_id)
          user.update_setting({
            'subscription' => {'last_expiring_week_notification' => Time.now.iso8601}
          })
          alerts[:upcoming_emailed] += 1
        end
      end
      
      now_expired = User.where(['expires_at > ? AND expires_at < ?', 3.days.ago, Time.now])
      # send out an expiration notification to all the ones that haven't been notified yet
      now_expired.each do |user|
        next unless user.communicator_role?
        alerts[:expired] += 1
        user.settings['subscription'] ||= {}
        last_expired = Time.parse(user.settings['subscription']['last_expired_notification']) rescue Time.at(0)
        if user.expires_at < Time.now && last_expired < 3.days.ago
          SubscriptionMailer.deliver_message(:subscription_expired, user.global_id)
          user.update_setting({
            'subscription' => {'last_expired_notification' => Time.now.iso8601}
          })
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
          user.update_setting({
            'subscription' => {'last_logging_reminder_notification' => Time.now.iso8601}
          })
          alerts[:recent_less_active] += 1
        end
      end
      alerts
    end
    
    def subscription_event(args)
      # ping from purchasing system, find the appropriate user and pass it along
      user = User.find_by_path(args['user_id'])
      return false unless user
      res = user.subscription_event(args)
      if args['cancel_others_on_update'] && res
        Purchasing.cancel_other_subscriptions(user, args['subscription_id'])
      end
      res
    end
  end
end