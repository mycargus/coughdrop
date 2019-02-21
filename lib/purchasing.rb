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
      if object && object['metadata'] && object['metadata']['type'] == 'extras'
        data = {:extras => true, :purchase_id => object['id'], :valid => true}
        if event['type'] == 'charge.succeeded'
          User.schedule(:purchase_extras, {
            'user_id' => object['metadata'] && object['metadata']['user_id'],
            'purchase_id' => object['id'],
            'customer_id' => object['customer'],
            'source' => 'charge.succeeded',
            'notify' => true
          })
        else
          data[:valid] = false
        end
      else
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
          if object['customer'] && object['customer'] != 'free'
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
                reason = 'Monthly payment unpaid' if object['status'] == 'unpaid'
                reason = 'Canceled by purchasing system' if object['status'] == 'canceled'
                User.schedule(:subscription_event, {
                  'unsubscribe' => true,
                  'user_id' => customer['metadata'] && customer['metadata']['user_id'],
                  'reason' => reason,
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
              'reason' => 'Deleted by purchasing system',
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
    end
    {:data => data, :status => 200}
  end
  
  def self.add_token_summary(token)
    return token unless token.is_a?(Hash)
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

  def self.extras_cost
    ENV['EXTRAS_COST'] || 25
  end

  def self.purchase(user, token, type, discount_code=nil)
    # TODO: record basic card information ("Visa ending in 4242" for references)
    user && user.log_subscription_event({:log => 'purchase initiated', :token => "#{token['id'][0,3]}..#{token['id'][-3,3]}", :type => type})
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    if type.match(/^slp_/) && type.match(/free/)
      if type.match(/plus_extras/)
        type = 'slp_long_term_free_plus_extras'
      else
        user.update_subscription({
          'subscribe' => true,
          'subscription_id' => 'free',
          'customer_id' => 'free',
          'plan_id' => 'slp_monthly_free'
        })
        Purchasing.cancel_other_subscriptions(user, 'all')
        return {success: true, type: type}
      end
    end
    user && user.log_subscription_event({:log => 'paid subscription'})
    amount = type.sub(/_plus_trial/, '').sub(/_plus_extras/, '').split(/_/)[-1].to_i
    include_extras = type.match(/plus_extras/)
    extras_added = false
    valid_amount = true
    description = type
    if type.match(/^slp_monthly/)
      valid_amount = false # unless [3, 4, 5].include?(amount)
      description = "CoughDrop supporter account"
    elsif type.match(/^slp_long_term/)
      valid_amount = false unless amount >= 50 #[50, 100, 150].include?(amount)
      if type.match(/free/)
        amount = 0
        valid_amount = true
      end
      description = "CoughDrop supporter account"
    elsif type.match(/^monthly/)
      valid_amount = false unless amount >= 6 #[3, 4, 5, 6, 7, 8, 9, 10].include?(amount)
      description = "CoughDrop communicator monthly subscription"
    elsif type.match(/^long_term/)
      valid_amount = false unless amount >= 150 #[150, 200, 250, 300].include?(amount)
      valid_amount = true if amount == 100 && self.active_sale?
      description = "CoughDrop communicator license purchase"
    else
      return {success: false, error: "unrecognized purchase type, #{type}"}
    end
    if !valid_amount
      user && user.log_subscription_event({:error => true, :log => 'invalid_amount'})
      return {success: false, error: "#{amount} not valid for type #{type}"}
    end
    plan_id = type.sub(/_plus_trial/, '').sub(/_plus_extras/, '')
    add_token_summary(token)
    begin
      if type.match(/long_term/)
        user && user.log_subscription_event({:log => 'long-term - creating charge'})
        if discount_code
          gift = GiftPurchase.find_by_code(discount_code) rescue nil
          return {success: false, error: "Invalid gift/discount code", code: discount_code} unless gift
          amount *= (1.0 - gift.discount_percent)
        end
        if include_extras
          amount += self.extras_cost 
          description += " (plus premium symbols)"
        end
    
        return {success: false, error: "Charge amount is zero"} if amount <= 0
        charge = Stripe::Charge.create({
          :amount => (amount * 100).to_i,
          :currency => 'usd',
          :source => token['id'],
          :description => description,
          :receipt_email => (user && user.external_email_allowed?) ? (user && user.settings && user.settings['email']) : nil,
          :metadata => {
            'user_id' => user.global_id,
            'plan_id' => plan_id,
            'type' => 'license'
          }
        })
        if include_extras
          extras_added = {:customer_id => charge['customer'], :purchase_id => charge['id']}
        end
        time = 5.years.to_i
        user && user.log_subscription_event({:log => 'persisting long-term purchase update'})
        if plan_id.match(/free/)
          user.update_subscription({
            'subscribe' => true,
            'subscription_id' => 'free',
            'customer_id' => 'free',
            'plan_id' => 'slp_monthly_free'
          })
        else
          User.subscription_event({
            'purchase' => true,
            'user_id' => user.global_id,
            'purchase_id' => charge['id'],
            'customer_id' => charge['customer'],
            'token_summary' => token['summary'],
            'discount_code' => discount_code,
            'purchase_amount' => amount,
            'plan_id' => plan_id,
            'seconds_to_add' => time,
            'source' => 'new purchase'
          })
        end
        cancel_other_subscriptions(user, 'all')
      else
        user && user.log_subscription_event({:log => 'monthly subscription'})
        customer = nil
        one_time_amount = amount
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
              :trial_end => trial_end
            })
          end
          customer = Stripe::Customer.retrieve(customer['id'])
          any_sub = customer.subscriptions.data.detect{|s| s.status == 'active' || s.status == 'trialing' }
          if include_extras
            one_time_amount += self.extras_cost
            charge_id = nil
            if customer['default_source']
              charge = Stripe::Charge.create({
                :amount => (self.extras_cost * 100),
                :currency => 'usd',
                :customer => customer['id'],
                :source => customer['default_source'],
                :receipt_email => user.settings['email'],
                :description => "CoughDrop premium symbols access",
                :metadata => {
                  'user_id' => user.global_id,
                  'type' => 'extras'
                }
              })
              charge_id = charge['id']
            else
              Stripe::InvoiceItem.create({
                amount: (self.extras_cost * 100),
                currency: 'usd',
                customer: customer['id'],
                description: 'CoughDrop premium symbols access'
              })
            end
            extras_added = {:customer_id => customer.id, :purchase_id => charge_id}
          end
          raise "no valid subscription found" unless any_sub
          user && user.log_subscription_event({:log => 'persisting subscription update'})
          updated = User.subscription_event({
            'subscribe' => true,
            'user_id' => user.global_id,
            'subscription_id' => sub['id'],
            'customer_id' => sub['customer'],
            'token_summary' => token['summary'],
            'purchase_amount' => one_time_amount,
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
      return {success: false, :trace => err.backtrace, error: 'unexpected_error', error_message: err.to_s, error_type: type, error_code: code}
    end
    if extras_added
      User.schedule(:purchase_extras, {
        'user_id' => user.global_id,
        'customer_id' => extras_added[:customer_id],
        'purchase_id' => extras_added[:purchase_id],
        'source' => 'purchase.include',
        'notify' => false
      })
    end
    {success: true, type: type}
  end
  
  def self.active_sale?
    !!(ENV['CURRENT_SALE'] && ENV['CURRENT_SALE'].to_i > Time.now.to_i)
  end

  def self.purchase_extras(token, opts)
    user = opts['user_id'] && User.find_by_global_id(opts['user_id'])
    return {success: false, error: 'user required'} unless user
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    amount = self.extras_cost
    add_token_summary(token)
    charge_type = false
    begin
      customer = nil
      if user && user.settings['subscription'] && user.settings['subscription']['customer_id'] && user.settings['subscription']['customer_id'] != 'free'
        customer = Stripe::Customer.retrieve(user.settings['subscription']['customer_id'])  rescue nil
      end
      # TODO: this is disabled for now, it's cleaner to just send everyone through the same purchase workflow
      # but it would be an easier sale if customers didn't have to do this
      if token == 'none' && customer && customer['subscriptions'].to_a.any?{|s| s['status'] == 'active' || s['status'] == 'trialing' }
        if customer['default_source']
          # charge the customer immediately if possible
          token = {'id' => customer['default_source'], 'customer_id' => customer['id']}
        end
        # TODO: you can create an InvoiceItem to add to an existing subscription
        # if for some reason a default_source is not defined, is this necessary?
      end
      if !charge_type && token != 'none'
        charge = Stripe::Charge.create({
          :amount => (amount * 100),
          :currency => 'usd',
          :source => token['id'],
          :customer => token['customer_id'],
          :receipt_email => user.settings['email'],
          :description => "CoughDrop premium symbols access",
          :metadata => {
            'user_id' => user.global_id,
            'type' => 'extras'
          }
        })
        charge_type = 'immediate_purchase'
        Worker.schedule_for(:priority, User, 'purchase_extras', {
          'user_id' => user.global_id,
          'purchase_id' => charge['id'],
          'customer_id' => charge['customer'],
          'source' => 'purchase.standalone',
          'notify' => true
        })
      elsif !charge_type
        return {success: false, error: 'token required without active subscription'}
      end
    rescue Stripe::CardError => err
      json = err.json_body
      err = json[:error]
      return {success: false, error: err[:code], decline_code: err[:decline_code]}
    rescue => err
      type = (err.respond_to?('[]') && err[:type])
      code = (err.respond_to?('[]') && err[:code]) || 'unknown'
      return {success: false, error: 'unexpected_error', error_message: err.to_s, error_type: type, error_code: code}
    end 
    {success: true, charge: charge_type}   
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
    cutoff = 150
    cutoff = 100 if self.active_sale?
    cutoff += 25 if opts['extras']
    cutoff += 50 if opts['donate']

    if type.match(/^long_term_custom/)
      if gift && gift.settings['amount']
        description = "#{gift.settings['licenses'] || 1} sponsored CoughDrop license(s)"
        if !gift.settings['memo'].blank?
          description += ", #{gift.settings['memo']}"
        end
      else
        valid_amount = false unless amount > cutoff
        description = "sponsored CoughDrop license"
      end
    elsif type.match(/^long_term/)
      valid_amount = false unless amount >= cutoff
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
        :receipt_email => (opts['email'] || (user && user.settings['email']) || '').strip,
        :description => description,
        :metadata => {
          'giver_id' => user && user.global_id,
          'giver_email' => opts['email'] || (user && user.settings['email']),
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
        'include_extras' => opts['extras'],
        'extra_donation' => opts['donate'],
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
    gift = GiftPurchase.find_by_code(code)
    if !user
      return {success: false, error: "user required"}
    end
    if !gift
      return {success: false, error: "code doesn't match any available gifts"}
    end
    if !gift.settings || gift.settings['seconds_to_add'].to_i <= 0
      return {success: false, error: "gift has no time to add"}
    end
    gift.redeem_code!(code, user)
    
    res = User.subscription_event({
      'user_id' => user.global_id,
      'purchase' => true,
      'plan_id' => 'gift_code',
      'gift_id' => gift.global_id,
      'code' => code,
      'seconds_to_add' => gift.settings['seconds_to_add'].to_i
    })
    if gift.settings['include_extras']
      User.purchase_extras({
        'user_id' => user.global_id,
        'source' => 'gift.redeemed'
      })
    end
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
      'subscription_id' => (user.settings['subscription'] || {})['subscription_id']
    })
    cancel_other_subscriptions(user, 'all')
  end
  
  def self.reconcile(with_side_effects=false)
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    customers = Stripe::Customer.list(:limit => 10)
    customer_active_ids = []
    total = 0
    cancel_months = {}
    cancels = {}
    output "retrieving expired subscriptions..."
    Stripe::Subscription.list(:limit => 20, :status => 'canceled').auto_paging_each do |sub|
      cancels[sub['customer']] ||= []
      cancels[sub['customer']] << sub
    end
    problems = []
    user_active_ids = []
    customers.auto_paging_each do |customer|
      total += 1
      cus_id = customer['id']
      email = customer['email']
      output "checking #{cus_id} #{email}"
      if !customer
        output "\tcustomer not found"
        next
      end
      user_id = customer['metadata'] && customer['metadata']['user_id']
      user = user_id && User.find_by_global_id(user_id)
      if !user
        problems << "#{customer['id']} no user found"
        output "\tuser not found"
        next
      end

      customer_subs = customer['subscriptions'].to_a
      user_active = user.recurring_subscription?
      user_active_ids << user.global_id if user_active
      customer_active = false
      
      if customer_subs.length > 1
        output "\ttoo many subscriptions"
        problems << "#{user.global_id} #{user.user_name} too many subscriptions"
      elsif user.long_term_purchase?
        subs = cancels[cus_id] || []
        sub = subs[0]
        str = "\tconverted to a long-term purchase"

        if sub && sub['canceled_at']
          canceled = Time.at(sub['canceled_at'])
          str += " on #{canceled.iso8601}"
        end
        if sub && sub['created']
          created = Time.at(customer['created'])
          str += ", subscribed #{created.iso8601}"
        end
        output str
        if customer_subs.length > 0
          sub = customer_subs[0]
          if sub && (sub['status'] == 'active' || sub['status'] == 'trialing')
            output "\tconverted to long-term purchase, but still has a lingering subscription"
            problems << "#{user.global_id} #{user.user_name} converted to long-term purchase, but still has a lingering subscription"
          end
        end
      elsif customer_subs.length == 0 
        # if no active subscription, this is an old customer record
        check_cancels = false
        # if customer id matches, then we are properly aligned
        if user.settings['subscription'] && user.settings['subscription']['customer_id'] == cus_id
          check_cancels = true
          if user_active
            output "\tno subscription found, but expected (FREELOADER)" 
            problems << "#{user.global_id} #{user.user_name} no subscription found, but expected (FREELOADER)"
          end
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
            if user_active
              output "\tuser active without a subscription (huh?)" 
              problems << "#{user.global_id} #{user.user_name} user active without a subscription (huh?)"
            end

          end
        else
          # if customer id doesn't match on subscription hash then we don't really care,
          # since there are no subscriptions for this customer, we just shouldn't
          # track this as a cancellation
          if user_active
          else
            check_cancels = true
          end
        end
        if check_cancels
          # Will only get here if there are no active subscriptions in purchasing system
          subs = cancels[cus_id] || []
          sub = subs[0]
          if sub
            canceled = Time.at(sub['canceled_at'])
            created = Time.at(customer['created'])
            # If canceled in the last 6 months, track it for reporting
            if canceled > 6.months.ago
              if user_active
                problems << "#{user.global_id} marked as canceled, but looks like still active"
              end 
              output "\tcanceled #{canceled.iso8601}, subscribed #{created.iso8601}, active #{user_active}" if canceled > 3.months.ago
              cancel_months[(canceled.year * 100) + canceled.month] ||= []
              cancel_months[(canceled.year * 100) + canceled.month] << (canceled - created) / 1.month.to_i
            end
          end
        end
      else
        sub = customer_subs[0]
        if user.settings['subscription'] && user.settings['subscription']['customer_id'] == cus_id
          customer_active = sub['status'] == 'active'
          customer_active_ids << user.global_id if customer_active
          if user_active != customer_active
            output "\tcustomer is #{sub['status']} but user is #{user_active ? 'subscribed' : 'expired'}" 
            problems << "#{user.global_id} #{user.user_name} customer is #{sub['status']} but user is #{user_active ? 'subscribed' : 'expired'}"
          end
        else
          # if customer id doesn't match on subscription hash:
          # - if the subscription is active, we have a problem
          # - otherwise we can ignore this customer record
          if user_active
            if sub['status'] == 'active' || sub['status'] == 'trialing'
              output "\tcustomer is #{sub['status']} but user is tied to a different customer record #{user.settings['subscription']['customer_id']}" 
              problems << "#{user.global_id} #{user.user_name} but user is tied to a different customer record #{user.settings['subscription']['customer_id']}"
            end
          end
        end
      end
    end
    if problems.length > 0
      output "PROBLEMS:\n#{problems.join("\n")}\n"
    end
    output "TOTALS: checked #{total}, paying customers (not trialing, not duplicates) #{customer_active_ids.uniq.length}, subscription users #{user_active_ids.uniq.length}"
    cancel_months.each{|k, a| 
      res = []
      res << (cancel_months[k].sum / cancel_months[k].length.to_f).round(1) 
      res << (cancel_months[k].length)
      cancel_months[k] = res
    }
    output "CANCELS: #{cancel_months.to_a.sort_by(&:first).reverse.to_json}"
  end

  def self.output(str)
    puts str
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
            # record the details of the cancellation, if there are any
            sub['metadata'] ||= {}
            sub['metadata']['cancel_reason'] = except_subscription_id
            sub.save
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