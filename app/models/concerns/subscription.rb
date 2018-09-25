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
      if self.settings['subscription']['subscription_id'] && self.settings['subscription']['customer_id']
        # If there is an existing subscription, schedule the API call to cancel it
        Worker.schedule(Purchasing, :cancel_subscription, self.global_id, self.settings['subscription']['customer_id'], self.settings['subscription']['subscription_id'])
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
    if Organization.managed?(self)
      self.settings['past_purchase_durations'] ||= []
      links = UserLink.links_for(self)
      links.select{|l| l['type'] == 'org_user' && l['state']['added'] }.each do |link|
        added = (link['state']['added'] && Time.parse(link['state']['added'])) rescue nil
        if added
          self.settings['past_purchase_durations'] << {type: 'org', started: link['state']['added'], duration: (Time.now.to_i - added.to_i)}
        end
      end
    end
    self.settings['managed_by'] = nil
    
    extra_expiration = opts[:allow_grace_period] ? 2.weeks.from_now : self.expires_at
    
    if self.settings['subscription']['org_sponsored']
      self.settings['subscription']['org_sponsored'] = nil
    end

    self.expires_at = [self.expires_at, extra_expiration].compact.max

    if self.settings['subscription']['last_purchase_plan_id'] && !self.settings['subscription']['last_purchase_plan_id'].match(/free/)
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
  
  def update_subscription_organization(org_id, pending=false, sponsored=true, eval_account=false)
    # used to pause subscription when the user is adopted by an organization, 
    # and possibly to resume the subscription when the user is dropped by an organization.
    prior_org = self.managing_organization
    link = nil
    if org_id && (!org_id.is_a?(String) || !org_id.match(/^r/))
      new_org = org_id.is_a?(Organization) ? org_id : Organization.find_by_global_id(org_id)
      if new_org && self.settings['authored_organization_id'] == new_org.global_id && self.created_at > 2.weeks.ago
        pending = false
      end
      self.settings['subscription'] ||= {}
      if new_org
#        Organization.detach_user(self, 'user', new_org)
      end
      if sponsored
        self.clear_existing_subscription(:track_seconds_left => true)
      end
      self.settings['subscription']['added_to_organization'] = Time.now.iso8601
      self.settings['subscription']['eval_account'] = true if eval_account
      self.settings['preferences'] ||= {}
      self.settings['preferences']['role'] = 'communicator'
      
      # Organizations can define a default home board for their users
      if new_org && new_org.settings['default_home_board'] && !self.settings['preferences']['home_board']
        home_board = Board.find_by_path(new_org.settings['default_home_board']['id'])
      self.assert_current_record!
        self.process_home_board({'id' => home_board.global_id}, {'updater' => home_board.user, 'async' => true}) if home_board
      end
      
      self.settings['pending'] = false
      if new_org
        link = UserLink.generate(self, new_org, 'org_user')
        if link.id && !link.data['state']['pending']
          pending = false
        end
        link.data['state']['added'] ||= Time.now.iso8601
        link.data['state']['pending'] = !!pending unless pending == nil
        link.data['state']['sponsored'] = !!sponsored unless sponsored == nil
        link.data['state']['eval'] = !!eval_account unless eval_account == nil
        new_org.schedule(:org_assertions, self.global_id, 'user')

        if sponsored && !pending
          self.expires_at = nil
          self.schedule(:process_subscription_token, 'token', 'unsubscribe')
        end
      end
      if !prior_org || prior_org != new_org
        UserMailer.schedule_delivery(:organization_assigned, self.global_id, new_org && new_org.global_id)
      end
      self.assert_current_record!
      res = self.save
      link.save if link
      return res
    else
      was_sponsored = self.org_sponsored?
      if org_id
        org_to_remove = Organization.find_by_global_id(org_id.sub(/^r/, ''))
        if org_to_remove
          org_to_remove.detach_user(self, 'user')
          UserMailer.schedule_delivery(:organization_unassigned, self.global_id, prior_org && prior_org.global_id)
        end
      end
      self.reload
      self.settings['subscription'] ||= {}
      self.clear_existing_subscription(:allow_grace_period => true) if was_sponsored && !self.org_sponsored?
      self.save
      # self.schedule(:update_subscription, {'resume' => true})
    end
  rescue ActiveRecord::StaleObjectError
    puts "stale :-/"
    self.schedule(:update_subscription_organization, org_id, pending, sponsored)
  end
  
  def transfer_subscription_to(user, skip_remote_update=false)
    transfer_keys = ['started', 'plan_id', 'subscription_id', 'token_summary', 'free_premium', 
      'never_expires', 'seconds_left', 'customer_id', 'last_purchase_plan_id', 'extras']
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
    user.expires_at = self.expires_at
    self.expires_at = Date.today + 60
    if did_change && !skip_remote_update
      Purchasing.change_user_id(user.settings['subscription']['customer_id'], self.global_id, user.global_id)
    end
    from_list = (user.settings['subscription']['transferred_from'] || []) + [self.global_id]
    user.update_setting({
      'expires_at' => user.expires_at,
      'subscription' => {'transferred_from' => from_list}
    })
    to_list = (self.settings['subscription']['transferred_to'] || []) + [user.global_id]
    self.update_setting({
      'expires_at' => self.expires_at,
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
          self.settings['subscription']['started'] = nil if args['plan_id'] == 'monthly_free' || args['plan_id'] == 'slp_monthly_free'
          self.settings['subscription']['token_summary'] = args['token_summary']
          self.settings['subscription']['plan_id'] = args['plan_id']
          self.settings['subscription']['purchase_amount'] = args['purchase_amount']
          self.settings['subscription']['eval_account'] = args['plan_id'] == 'eval_monthly_free'
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
        self.settings['subscription']['unsubscribe_reason'] = args['reason'] if args['reason']
        self.settings['pending'] = false
        self.assert_current_record!
        self.save
        if self.settings['subscription']['unsubscribe_reason'] && !self.long_term_purchase?
          SubscriptionMailer.schedule_delivery(:unsubscribe_reason, self.global_id)
        end
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
          self.settings['subscription']['discount_code'] = args['discount_code'] if args['discount_code']
          self.settings['subscription']['last_purchase_seconds_added'] = args['seconds_to_add']
          self.settings['subscription']['purchase_amount'] = args['purchase_amount']
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

  def process_subscription_token(token, type, code=nil)
    if type == 'unsubscribe'
      Purchasing.unsubscribe(self)
    elsif type == 'extras'
      Purchasing.purchase_extras(token, {'user_id' => self.global_id})
    else
      Purchasing.purchase(self, token, type, code)
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
    elsif type == 'enable_extras'
      User.purchase_extras({
        'user_id' => self.global_id,
        'source' => 'admin_override'
      })
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
  
  def paid_or_sponsored?
    !!(never_expires? || self.recurring_subscription? || self.long_term_purchase? || self.fully_purchased?(true) || self.org_sponsored? )
  end
  
  def premium?
    !!(self.paid_or_sponsored? || self.grace_period? || self.free_premium?)
  end

  def full_premium?
    !!(self.premium? && !self.free_premium? && !self.grace_period?)
  end
  
  def eval_account?
    !!(self.settings && self.settings['subscription'] && self.settings['subscription']['eval_account'])
  end
  
  def reset_eval(current_device)
    duration = self.eval_duration
    self.settings['subscription'] ||= {}
    self.settings['subscription']['eval_account'] = true
    # reset the eval expiration clock
    self.settings['subscription']['eval_started'] = Time.now.iso8601
    self.settings['subscription']['eval_expires'] = duration.days.from_now.iso8601
    # clear/reset preferences (remember them so they can be transferred
    self.settings['last_preferences'] = self.settings['preferences'] || {}
    self.settings['preferences'] = nil
    self.generate_defaults
    # keep the last home board, in case it's a default (can be changed easily)
    self.settings['preferences']['home_board'] = self.settings['last_preferences']['home_board']
    # log out of all other devices (and remove them for privacy)
    self.devices.select{|d| d != current_device}.each{|d| d.destroy }
    # enable logging by default
    self.settings['preferences']['logging'] = true
    # flush all old logs
    progress = Progress.schedule(Flusher, :flush_user_logs, self.global_id, self.user_name)
    self.save
  end
  
  def transfer_eval_to(destination_user, current_device)
    device_key = current_device.unique_device_key
    devices = destination_user.settings['preferences']['devices'] || {}
    devices[device_key] = self.settings['preferences']['devices'][device_key] if self.settings['preferences']['devices'][device_key]
    destination_user.settings['preferences'] = destination_user.settings['preferences'].merge(self.settings['preferences'])
    destination_user.settings['preferences']['devices'] = devices
    destination_user.save
    # transfer usage logs to the new user
    eval_start = Time.parse((self.settings['subscription'] || {})['eval_started'] || 60.days.ago.iso8601)
    WeeklyStatsSummary.where(user_id: self.id).where(['created_at > ?', eval_start]).each do |summary|
      summary.schedule(:update!)
    end
    LogSession.where(user_id: self.id, log_type: ['session', 'note', 'assessment']).where(['started_at >= ?', eval_start]).each do |session|
      session.user_id = destination_user.id
      session.save
    end
    # TODO: transfer daily_use data across as well
    self.reset_eval(current_device)
  end
  
  def eval_duration
    self.settings['eval_duration'] || self.class.default_eval_duration
  end
  
  
  def org_sponsored?
    Organization.sponsored?(self)
  end
  
  def purchase_credit_duration
    # long-term purchase, org-sponsored, or subscription duration for the current user
    past_tally = (self.settings['past_purchase_durations'] || []).map{|d| d['duration'] || 0}.sum
    return past_tally if past_tally > 2.years
    started = nil
    # for a long-term purchase, track from when the purchase happened
    if self.settings['subscription'] && self.settings['subscription']['last_purchased'] && self.expires_at
      started = Time.parse(self.settings['subscription']['last_purchased']) rescue nil
    end
    if self.recurring_subscription?
      # for a recurrind subscription, track from when the subscription started
      started = Time.parse(self.settings['subscription']['started']) rescue nil
    elsif self.org_sponsored?
      # for an org sponsorship, track the duration of the sponsorship
      sponsor_dates = UserLink.links_for(self).select{|l| l['type'] == 'org_user' && l['state']['sponsored'] == true}.map{|l| l['state']['added'] }
      started = Time.parse(sponsor_dates.sort.first) rescue nil
    end
    tally = past_tally
    if !self.grace_period?
      tally += [self.expires_at, Time.now].compact.min.to_i - [started, Time.now].compact.min.to_i
    end
    return tally
  end
  
  def fully_purchased?(shallow=false)
    # long-term purchase, org-sponsored, or subscription for at least 2 years
    past_tally = ((self.settings || {})['past_purchase_durations'] || []).map{|d| d['duration'] || 0}.sum
    return true if past_tally > (2.years - 1.week)
    return false if shallow
    duration = self.purchase_credit_duration
    return duration > (2.years - 1.week)
  end
  
  def free_premium?
    if self.supporter_role? && self.expires_at && self.expires_at < Time.now && !self.long_term_purchase?
      self.schedule(:subscription_override, 'manual_supporter')
      return true
    elsif self.supporter_registration? && self.communicator_role? && self.expires_at && self.expires_at < Time.now && !self.paid_or_sponsored?
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
    !!(self.expires_at && self.expires_at > Time.now && !self.paid_or_sponsored?)
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
      json['eval_account'] = self.eval_account?
    else
      json['expires'] = self.expires_at && self.expires_at.iso8601
      json['grace_period'] = self.grace_period?
      if self.recurring_subscription?
        json['active'] = true
        json['started'] = self.settings['subscription']['started']
        json['plan_id'] = self.settings['subscription']['plan_id']
        json['free_premium'] = self.settings['subscription']['free_premium'] if self.free_premium?
        json['eval_account'] = self.eval_account?
      elsif self.long_term_purchase?
        json['active'] = true
        json['purchased'] = self.settings['subscription']['customer_id'] != 'free'
        json['plan_id'] = self.settings['subscription']['last_purchase_plan_id']
        json['free_premium'] = self.settings['subscription']['free_premium'] if self.free_premium?
      elsif self.settings['subscription']['free_premium']
        json['active'] = true
        json['free_premium'] = self.settings['subscription']['free_premium']
        json['plan_id'] = self.settings['subscription']['plan_id']
      end
    end
    json['extras_enabled'] = true if self.settings['subscription']['extras'] && self.settings['subscription']['extras']['enabled']
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
      alerts = {:approaching => 0, :approaching_emailed => 0, :upcoming => 0, :upcoming_emailed => 0, :expired => 0, :expired_emailed => 0, :expired_follow_up => 0, :recent_less_active => 0, :pending_deletes => 0}
      
      # send out a one-month and three-month warning for long-term purchase subscriptions
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
      
      recently_expired = User.where(['expires_at > ? AND expires_at < ?', 3.weeks.ago, 2.weeks.ago])
      recently_expired.each do |user|
        user.settings['subscription'] ||= {}
        last_recently_expired = Time.parse(user.settings['subscription']['last_expired_follow_up']) rescue Time.at(0)
        if last_recently_expired < 6.months.ago
          if user.communicator_role?
            # message asking why they didn't go with it
          else
            # if inactive, message asking why they aren't super stoked about it
          end
          alerts[:expired_follow_up] += 1
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

      # send out a two and one-month warning when account is 
      # going to be deleted for inactivity (after 12 months of non-use)
      to_be_deleted = User.where(['updated_at < ?', 12.months.ago]).order('updated_at ASC').limit(100)
      to_be_deleted.each do |user|
        next if user.user_name.match(/^testing/) && user.settings['email'] == 'testing@example.com'
        updated = user.updated_at
        user.settings['subscription'] ||= {}
        last_warning = Time.parse(user.settings['subscription']['last_deletion_warning']) rescue Time.at(0)
        if last_warning < 3.weeks.ago
          attempts = 1
          if last_warning > 20.weeks.ago
            attempts = (user.settings['subscription']['last_deletion_attempts'] || 0) + 1
          end
          if attempts > 2
            user.schedule_deletion_at = 36.hours.from_now
            user.save
            SubscriptionMailer.deliver_message(:account_deleted, user.global_id)
          else
            SubscriptionMailer.deliver_message(:deletion_warning, user.global_id, attempts)
            alerts[:pending_deletes] += 1
            user.update_setting({
              'subscription' => {
                'last_deletion_warning' => Time.now.iso8601,
                'last_deletion_attempts' => attempts
              }
            })
          end
          User.where(id: user.id).update_all(updated_at: 12.months.ago + 3.weeks)
        end
      end
      alerts
    end

    def default_eval_duration
      60
    end

    def purchase_extras(opts)
      user = User.find_by_global_id(opts['user_id'])
      raise "user not found" unless user
      user.settings['subscription'] ||= {}
      first_enabling = !(user.settings['subscription']['extras'] && user.settings['subscription']['extras']['enabled'])
      user.settings['subscription']['extras'] = (user.settings['subscription']['extras'] || {}).merge({
        'enabled' => true,
        'purchase_id' => opts['purchase_id'],
        'customer_id' => opts['customer_id'],
        'source' => opts['source']
      })
      user.settings['subscription']['extras']['sources'] ||= []
      user.settings['subscription']['extras']['sources'] << {
        'timestamp' => Time.now.to_i,
        'customer_id' => opts['customer_id'],
        'source' => opts['source']
      }
      user.save!
      if first_enabling
        AuditEvent.create!(:event_type => 'extras_added', :summary => "#{user.user_name} activated extras", :data => {source: opts['source']})
      end
      if first_enabling && opts['notify']
        SubscriptionMailer.schedule_delivery(:extras_purchased, user.global_id)
      end
      true
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