require 'stripe'

module Purchasing
  def self.subscription_event(request)
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    json = JSON.parse(request.body.read) rescue nil
    event_id = json && json['id']
    event = event_id && Stripe::Event.retrieve(event_id) rescue nil
    if !event || !event['type']
      return {:data => {:error => "invalid parameters", :event_id => event_id}, :status => event_id ? 200 : 400}
    end
    data = {:valid => false, :type => event['type'], :event_id => event_id}
    object = event['data'] && event['data']['object']
    previous = event['data'] && event['data']['previous_attributes']
    event_result = nil
    if object
      if event['type'] == 'charge.succeeded'
        valid = object['metadata'] && object['metadata']['user_id'] && object['metadata']['plan_id']
        if valid
          time = 5.years.to_i
          User.schedule(:subscription_event, {
            'purchase' => true,
            'user_id' => object['metadata'] && object['metadata']['user_id'],
            'purchase_id' => object['id'],
            'customer_id' => object['customer'],
            'plan_id' => object['metadata'] && object['metadata']['plan_id'],
            'seconds_to_add' => time,
            'source' => 'charge.succeeded'
          })
        end
        data = {:purchase => true, :purchase_id => object['id'], :valid => !!valid}
      elsif event['type'] == 'charge.failed'
        valid = false
        if object['customer']
          customer = Stripe::Customer.retrieve(object['customer'])
          valid = customer && customer['metadata'] && customer['metadata']['user_id']

          if valid
            User.schedule(:subscription_event, {
              'user_id' => customer['metadata'] && customer['metadata']['user_id'],
              'purchase_failed' => true,
              'source' => 'charge.failed'
            })
          end
        end
        data = {:purchase => false, :notified => true, :valid => !!valid}
      elsif event['type'] == 'charge.dispute.created'
        charge = Stripe::Charge.retrieve(object['id'])
        if charge
          valid = charge['metadata'] && charge['metadata']['user_id']
          if valid
            User.schedule(:subscription_event, {
              'user_id' => charge['metadata'] && charge['metadata']['user_id'],
              'chargeback_created' => true,
              'source' => 'charge.dispute.created'
            })
          end
          data = {:dispute => true, :notified => true, :valid => !!valid}
        end
      elsif event['type'] == 'customer.updated'
        customer = Stripe::Customer.retrieve(object['id'])
        valid = customer && customer['metadata'] && customer['metadata']['user_id']
        previous = event['data'] && event['data']['previous_attributes'] && event['data']['previous_attributes']['metadata'] && event['data']['previous_attributes']['metadata']['user_id']
        if valid && previous
          prior_user = User.find_by_global_id(previous)
          new_user = User.find_by_global_id(valid)
          if prior_user && new_user && prior_user.settings['subscription'] && prior_user.settings['subscription']['customer_id'] == object['id']
            # TODO: move to background job..
            prior_user.transfer_subscription_to(new_user, true)
          end
        end
      elsif event['type'] == 'customer.subscription.created'
        customer = Stripe::Customer.retrieve(object['customer'])
        valid = customer && customer['metadata'] && customer['metadata']['user_id'] && object['plan'] && object['plan']['id']
        if valid
          User.schedule(:subscription_event, {
            'subscribe' => true,
            'user_id' => customer['metadata'] && customer['metadata']['user_id'],
            'customer_id' => object['customer'],
            'subscription_id' => object['id'],
            'plan_id' => object['plan'] && object['plan']['id'],
            'cancel_others_on_update' => true,
            'source' => 'customer.subscription.created'
          })
        end
        data = {:subscribe => true, :valid => !!valid}
      elsif event['type'] == 'customer.subscription.updated'
        customer = Stripe::Customer.retrieve(object['customer'])
        valid = customer && customer['metadata'] && customer['metadata']['user_id']
        if object['status'] == 'unpaid' || object['status'] == 'canceled'
          if previous && previous['status'] && previous['status'] != 'unpaid' && previous['status'] != 'canceled'
            if valid
              User.schedule(:subscription_event, {
                'unsubscribe' => true,
                'user_id' => customer['metadata'] && customer['metadata']['user_id'],
                'customer_id' => object['customer'],
                'subscription_id' => object['id'],
                'cancel_others_on_update' => false,
                'source' => 'customer.subscription.updated'
              })
            end
            data = {:unsubscribe => true, :valid => !!valid}
          end
        elsif object['status'] == 'active' || object['status'] == 'trialing'
          if valid
            User.schedule(:subscription_event, {
              'subscribe' => true,
              'user_id' => customer['metadata'] && customer['metadata']['user_id'],
              'customer_id' => object['customer'],
              'subscription_id' => object['id'],
              'plan_id' => object['plan'] && object['plan']['id'],
              'cancel_others_on_update' => true,
              'source' => 'customer.subscription.updated'
            })
          end
          data = {:subscribe => true, :valid => !!valid}
        end
      elsif event['type'] == 'customer.subscription.deleted'
        customer = Stripe::Customer.retrieve(object['customer'])
        valid = customer && customer['metadata'] && customer['metadata']['user_id']
        if valid
          User.schedule(:subscription_event, {
            'unsubscribe' => true,
            'user_id' => customer['metadata'] && customer['metadata']['user_id'],
            'customer_id' => object['customer'],
            'subscription_id' => object['id'],
            'source' => 'customer.subscription.deleted'
          })
        end
        data = {:unsubscribe => true, :valid => !!valid}
      elsif event['type'] == 'ping'
        data = {:ping => true, :valid => true}
      end
    end
    {:data => data, :status => 200}
  end
  
  def self.add_token_summary(token)
    token['summary'] = "Unknown Card"
    brand = token['card'] && token['card']['brand']
    last4 = token['card'] && token['card']['last4']
    exp_year = token['card'] && token['card']['exp_year']
    exp_month = token['card'] && token['card']['exp_month']
    if brand && last4
      token['summary'] = brand + " card ending in " + last4
      if exp_year && exp_month
        token['summary'] += " (exp #{exp_month}/#{exp_year})"
      end
    end
    token['summary']
  end

  def self.purchase(user, token, type)
    # TODO: record basic card information ("Visa ending in 4242" for references)
    user && user.log_subscription_event({:log => 'purchase initiated', :token => "#{token['id'][0,3]}..#{token['id'][-3,3]}", :type => type})
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    if type.match(/^slp_/) && type.match(/free/)
      user.update_subscription({
        'subscribe' => true,
        'subscription_id' => 'free',
        'customer_id' => 'free',
        'plan_id' => 'slp_monthly_free'
      })
      Purchasing.cancel_other_subscriptions(user, 'all')
      return {success: true, type: type}
    end
    user && user.log_subscription_event({:log => 'paid subscription'})
    amount = type.sub(/_plus_trial/, '').split(/_/)[-1].to_i
    valid_amount = true
    description = type
    if type.match(/^slp_monthly/)
      valid_amount = false unless [3, 4, 5].include?(amount)
      description = "CoughDrop supporter monthly subscription"
    elsif type.match(/^slp_long_term/)
      valid_amount = false unless [50, 100, 150].include?(amount)
      description = "CoughDrop supporter license purchase"
    elsif type.match(/^monthly/)
      valid_amount = false unless [3, 4, 5, 6, 7, 8, 9, 10].include?(amount)
      description = "CoughDrop communicator monthly subscription"
    elsif type.match(/^long_term/)
      valid_amount = false unless [150, 200, 250, 300].include?(amount)
      valid_amount = true if amount == 100 && self.active_sale?
      description = "CoughDrop communicator license purchase"
    else
      return {success: false, error: "unrecognized purchase type, #{type}"}
    end
    if !valid_amount
      user && user.log_subscription_event({:error => true, :log => 'invalid_amount'})
      return {success: false, error: "#{amount} not valid for type #{type}"}
    end
    plan_id = type
    add_token_summary(token)
    begin
      if type.match(/long_term/)
        user && user.log_subscription_event({:log => 'long-term - creating charge'})
        charge = Stripe::Charge.create({
          :amount => (amount * 100),
          :currency => 'usd',
          :source => token['id'],
          :description => description,
          :receipt_email => (user && user.external_email_allowed?) ? (user && user.settings && user.settings['email']) : nil,
          :metadata => {
            'user_id' => user.global_id,
            'plan_id' => plan_id
          }
        })
        time = 5.years.to_i
        user && user.log_subscription_event({:log => 'persisting long-term purchase update'})
        User.subscription_event({
          'purchase' => true,
          'user_id' => user.global_id,
          'purchase_id' => charge['id'],
          'customer_id' => charge['customer'],
          'token_summary' => token['summary'],
          'plan_id' => plan_id,
          'seconds_to_add' => time,
          'source' => 'new purchase'
        })
        cancel_other_subscriptions(user, 'all')
      else
        user && user.log_subscription_event({:log => 'monthly subscription'})
        customer = nil
        if user.settings['subscription'] && user.settings['subscription']['customer_id'] && user.settings['subscription']['customer_id'] != 'free'
          user && user.log_subscription_event({:log => 'retrieving existing customer'})
          customer = Stripe::Customer.retrieve(user.settings['subscription']['customer_id']) rescue nil
        end
        if !customer
          user && user.log_subscription_event({:log => 'creating new customer'})
          customer = Stripe::Customer.create({
            :metadata => {
              'user_id' => user.global_id
            },
            :email => (user && user.external_email_allowed?) ? (user && user.settings && user.settings['email']) : nil
          })
        end
        if customer
          user && user.log_subscription_event({:log => 'new subscription for existing customer'})
          sub = nil
          if customer.subscriptions.count > 0
            sub = customer.subscriptions.data.detect{|s| s.status == 'active' || s.status == 'past_due' || s.status == 'unpaid' }
          end
          if sub
            sub.source = token['id']
            sub.plan = plan_id
            sub.prorate = true
            sub.save
          else
            trial_end = 'now'
            if user.created_at > 60.days.ago
              trial_end = (user.created_at + 60.days).to_i
            end
            sub = customer.subscriptions.create({
              :plan => plan_id,
              :source => token['id'],
              # TODO: uncomment this to let people finish their free trial before being charged
              :trial_end => trial_end
            })
          end
          customer = Stripe::Customer.retrieve(customer.id)
          any_sub = customer.subscriptions.data.detect{|s| s.status == 'active' || s.status == 'trialing' }
          raise "no valid subscription found" unless any_sub
          user && user.log_subscription_event({:log => 'persisting subscription update'})
          updated = User.subscription_event({
            'subscribe' => true,
            'user_id' => user.global_id,
            'subscription_id' => sub['id'],
            'customer_id' => sub['customer'],
            'token_summary' => token['summary'],
            'plan_id' => plan_id,
            'cancel_others_on_update' => true,
            'source' => 'new subscription'
          })
        else
          raise "customer should have been created but wasn't"
        end
      end
    rescue Stripe::CardError => err
      json = err.json_body
      err = json[:error]
      user && user.log_subscription_event({:error => 'stripe card_exception', :json => json})
      return {success: false, error: err[:code], decline_code: err[:decline_code]}
    rescue => err
      type = (err.respond_to?('[]') && err[:type])
      code = (err.respond_to?('[]') && err[:code]) || 'unknown'
      user && user.log_subscription_event({:error => 'other_exception', :err => err.to_s + err.backtrace[0].to_s })
      return {success: false, error: 'unexpected_error', error_message: err.to_s, error_type: type, error_code: code}
    end
    {success: true, type: type}
  end
  
  def self.active_sale?
    !!(ENV['CURRENT_SALE'] && ENV['CURRENT_SALE'].to_i > Time.now.to_i)
  end
  
  def self.purchase_gift(token, opts)
    user = opts['user_id'] && User.find_by_global_id(opts['user_id'])
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    type = opts['type'] || ""
    amount = type.split(/_/)[-1].to_i
    valid_amount = true
    description = type
    seconds = 5.years.to_i

    gift = GiftPurchase.find_by_code(opts['code']) if opts['code']

    if type.match(/^long_term_custom/)
      if gift && gift.settings['amount']
        description = "#{gift.settings['licenses'] || 1} sponsored CoughDrop license(s)"
        if !gift.settings['memo'].blank?
          description += ", #{gift.settings['memo']}"
        end
      else
        valid_amount = false unless amount > 100 && (amount % 50) == 0
        description = "sponsored CoughDrop license"
      end
    elsif type.match(/^long_term/)
      valid_amount = false unless [150, 200, 250, 300].include?(amount)
      valid_amount = true if amount == 100 && self.active_sale?
      description = "sponsored CoughDrop license"
    else
      return {success: false, error: "unrecognized purchase type, #{type}"}
    end    
    if !valid_amount
      return {success: false, error: "#{amount} not valid for type #{type}"}
    end
    add_token_summary(token)
    begin
      charge = Stripe::Charge.create({
        :amount => (amount * 100),
        :currency => 'usd',
        :source => token['id'],
        :description => description,
        :metadata => {
          'giver_id' => user && user.global_id,
          'giver_email' => opts['email'],
          'plan_id' => type
        }
      })
      gift ||= GiftPurchase.process_new({}, {
        'giver' => user, 
        'email' => opts['email'],
        'seconds' => seconds
      })
      gift.process({}, {
        'customer_id' => charge['customer'],
        'token_summary' => token['summary'],
        'plan_id' => type,
        'purchase_id' => charge['id'],
      })
      gift.notify_of_creation
    rescue Stripe::CardError => err
      json = err.json_body
      err = json[:error]
      return {success: false, error: err[:code], decline_code: err[:decline_code]}
    rescue => err
      type = (err.respond_to?('[]') && err[:type])
      code = (err.respond_to?('[]') && err[:code]) || 'unknown'
      return {success: false, error: 'unexpected_error', error_message: err.to_s, error_type: type, error_code: code}
    end
    {success: true, type: type}
  end
  
  def self.redeem_gift(code, user)
    gift = GiftPurchase.where(:active => true, :code => code).first
    if !user
      return {success: false, error: "user required"}
    end
    if !gift
      return {success: false, error: "code doesn't match any available gifts"}
    end
    if !gift.settings || gift.settings['seconds_to_add'].to_i <= 0
      return {success: false, error: "gift has no time to add"}
    end
    gift.active = false
    gift.settings['receiver_id'] = user.global_id
    gift.settings['redeemed_at'] = Time.now.iso8601
    gift.save
    
    res = User.subscription_event({
      'user_id' => user.global_id,
      'purchase' => true,
      'plan_id' => 'gift_code',
      'gift_id' => gift.global_id,
      'seconds_to_add' => gift.settings['seconds_to_add'].to_i
    })
    if res
      {success: true, redeemed: true, code: code}
    else
      {success: false, error: "unexpected_error"}
    end
  end
  
  def self.change_user_id(customer_id, from_user_id, to_user_id)
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    customer = Stripe::Customer.retrieve(customer_id) rescue nil
    if customer
      raise "wrong existing user_id" unless customer.metadata && customer.metadata['user_id'] == from_user_id
      customer.metadata['user_id'] = to_user_id
      customer.save
    else
      raise "customer not found"
    end
  end
  
  def self.unsubscribe(user)
    return false unless user
    User.subscription_event({
      'unsubscribe' => true,
      'manual_unsubscribe' => true,
      'user_id' => user.global_id,
      'customer_id' => (user.settings['subscription'] || {})['customer_id'],
      'subscription_id' => user.settings['subscription']['subscription_id']
    })
    cancel_other_subscriptions(user, 'all')
  end
  
  def self.reconcile(with_side_effects=false)
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    customers = Stripe::Customer.list(:limit => 10)
    customer_actives = 0
    user_actives = 0
    total = 0
    cancel_months = {}
    cancels = {}
    puts "retrieving expired subscriptions..."
    Stripe::Subscription.list(:limit => 20, :status => 'canceled').auto_paging_each do |sub|
      cancels[sub['customer']] ||= []
      cancels[sub['customer']] << sub
    end
    customers.auto_paging_each do |customer|
      total += 1
      cus_id = customer['id']
      email = customer['email']
      puts "checking #{cus_id} #{email}"
      if !customer
        puts "\tcustomer not found"
        next
      end
      user_id = customer['metadata'] && customer['metadata']['user_id']
      user = user_id && User.find_by_global_id(user_id)
      if !user
        puts "\tuser not found"
        next
      end

      customer_subs = customer['subscriptions'].to_a
      user_active = user.recurring_subscription?
      user_actives += 1 if user_active
      customer_active = false
      
      if customer_subs.length > 1
        puts "\ttoo many subscriptions"
      elsif customer_subs.length == 0 
        check_cancels = false
        if user.settings['subscription'] && user.settings['subscription']['customer_id'] == cus_id
          check_cancels = true
          puts "\tno subscription found, but expected (FREELOADER)" if user_active
          if user_active && with_side_effects
            User.schedule(:subscription_event, {
              'unsubscribe' => true,
              'user_id' => user.global_id,
              'customer_id' => cus_id,
              'subscription_id' => object['id'],
              'cancel_others_on_update' => true,
              'source' => 'customer.reconciliation'
            })
          else
            puts "\tuser active without a subscription (huh?)" if user_active
          end
        else
          if user_active
            puts "\tuser active and tied to a different customer id, #{user.settings['subscription']['customer_id']}"
            user_actives -= 1
          else
            check_cancels = true
          end
        end
        if check_cancels
          subs = cancels[cus_id] || []
          sub = subs[0]
          if sub
            canceled = Time.at(sub['canceled_at'])
            created = Time.at(customer['created'])
            if canceled > 6.months.ago
              cancel_months[(canceled.year * 100) + canceled.month] ||= []
              cancel_months[(canceled.year * 100) + canceled.month] << (canceled - created) / 1.month.to_i
            end
          end
        end
      else
        sub = customer_subs[0]
        customer_active = sub['status'] == 'active'
        customer_actives += 1 if customer_active
        puts "\tcustomer is #{sub['status']} but user is #{user_active ? 'subscribed' : 'expired'}" if user_active != customer_active
      end
    end
    puts "TOTALS: checked #{total}, paying customers (not trialing, not duplicates) #{customer_actives}, subscription users #{user_actives}"
    cancel_months.each{|k, a| 
      res = []
      res << (cancel_months[k].sum / cancel_months[k].length.to_f).round(1) 
      res << (cancel_months[k].length)
      cancel_months[k] = res
    }
    puts "CANCELS: #{cancel_months.to_a.sort_by(&:first).reverse.to_json}"
  end
  
  def self.cancel_subscription(user_id, customer_id, subscription_id)
    user = User.find_by_global_id(user_id)
    return false unless user
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    begin
      customer = Stripe::Customer.retrieve(customer_id)
    rescue => e
      user.log_subscription_event({:log => 'subscription canceling error', :detail => 'error retrieving customer', :error => e.to_s, :trace => e.backtrace})
    end
    
    if customer
      if !customer.metadata || customer.metadata['user_id'] != user_id
        return false
      end
      
      begin
        customer_subs = customer.subscriptions.all.to_a
        sub = customer_subs.detect{|s| s['id'] == subscription_id}
      rescue => e
        user.log_subscription_event({:log => 'subscription canceling error', :detail => 'error retrieving subscriptions', :error => e.to_s, :trace => e.backtrace})
      end
      
      if sub && sub['status'] != 'canceled' && sub['status'] != 'past_due'
        begin
          sub.delete
          user.log_subscription_event({:log => 'subscription canceling success', id: sub['id'], reason: subscription_id})
          return true
        rescue => e
          user.log_subscription_event({:log => 'subscription canceling error', :detail => 'error canceling subscription', :error => e.to_s, :trace => e.backtrace})
        end
      end
    end
    false
  end
  
  def self.cancel_other_subscriptions(user, except_subscription_id)
    return false unless user && user.settings && user.settings['subscription']
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    user.log_subscription_event({:log => 'subscription canceling', reason: except_subscription_id}) if user
    customer_ids = []
    # cancel all subscriptions tied to the user, even if their customer_id has changed in the mean time
    customer_ids << user.settings['subscription']['customer_id'] if user.settings['subscription']['customer_id']
    customer_ids += user.settings['subscription']['prior_customer_ids'] || []
    customer_ids = customer_ids.select{|id| id && id != 'free' }
    # need to collect subscriptions for all affiliated customer_ids to try to find the right exception
    subs = []
    customer_ids.each do |customer_id|
      begin
        customer = Stripe::Customer.retrieve(customer_id)
      rescue => e
        user.log_subscription_event({:log => 'subscription cancel error', :detail => 'error retrieving customer', :error => e.to_s, :trace => e.backtrace}) if user
      end
      if customer
        begin
          customer_subs = customer.subscriptions.all.to_a
          subs += customer_subs
        rescue => e
          user.log_subscription_event({:log => 'subscription cancel error', :detail => 'error retrieving subscriptions', :error => e.to_s, :trace => e.backtrace}) if user
          return false
        end
      else
        return false
      end
    end
    do_cancel = (except_subscription_id == 'all')
    subs.each do |sub|
      # plan to cancel all other subscriptions if the specified one is active
      if sub['id'] == except_subscription_id && sub['status'] != 'canceled' && sub['status'] != 'past_due'
        do_cancel = true
      end
    end
    if do_cancel
      subs.each do |sub|
        # don't cancel the specified subscription
        if sub['id'] == except_subscription_id && except_subscription_id != 'all'
        else
          begin
            sub.delete
            user.log_subscription_event({:log => 'subscription canceled', id: sub['id'], reason: except_subscription_id}) if user
          rescue => e
            user.log_subscription_event({:log => 'subscription cancel error', :detail => 'error deleting subscription', :subscription_id => sub['id'], :error => e.to_s, :trace => e.backtrace}) if user
            return false
          end
        end
      end
    end
    true
  end
  
  def self.pause_subscription(user)
    # API call
    return false
  end
  
  def self.resume_subscription(user)
    # API call
    return false
  end
end