class SubscriptionMailer < ActionMailer::Base
  include General
  default from: ENV['DEFAULT_EMAIL_FROM']
  layout 'email'
  
  def chargeback_created(user_id)
    @user = User.find_by_global_id(user_id)
    if ENV['SYSTEM_ERROR_EMAIL']
      mail(to: ENV['SYSTEM_ERROR_EMAIL'], subject: "CoughDrop - Chargeback Created")
    end
  end

  def subscription_pause_failed(user_id)
    @user = User.find_by_global_id(user_id)
    if ENV['SYSTEM_ERROR_EMAIL']
      mail(to: ENV['SYSTEM_ERROR_EMAIL'], subject: "CoughDrop - Subscription Pause Failed")
    end
  end

  def new_subscription(user_id)
    @user = User.find_by_global_id(user_id)
    @subscription = @user.subscription_hash
    if ENV['NEW_REGISTRATION_EMAIL']
      mail(to: ENV['NEW_REGISTRATION_EMAIL'], subject: "CoughDrop - New Subscription")
    end
  end
  
  def subscription_resume_failed(user_id)
    @user = User.find_by_global_id(user_id)
    mail_message(@user, "Subscription Needs Attention")
  end
  
  def purchase_bounced(user_id)
    @user = User.find_by_global_id(user_id)
    mail_message(@user, "Problem with your Subscription")
  end
  
  def purchase_confirmed(user_id)
    @user = User.find_by_global_id(user_id)
    mail_message(@user, "Subscription Confirmed")
  end
  
  def expiration_approaching(user_id)
    @user = User.find_by_global_id(user_id)
    mail_message(@user, "Subscription Notice")
  end
  
  def one_day_until_expiration(user_id)
    @user = User.find_by_global_id(user_id)
    mail_message(@user, "Subscription Notice")
  end
  
  def one_week_until_expiration(user_id)
    @user = User.find_by_global_id(user_id)
    mail_message(@user, "Subscription Notice")
  end
  
  def subscription_expired(user_id)
    @user = User.find_by_global_id(user_id)
    mail_message(@user, "Subscription Expired")
  end

  def subscription_expiring(user_id)
    @user = User.find_by_global_id(user_id)
    mail_message(@user, "Subscription Needs Attention")
  end
  
  def gift_created(gift_id)
    @gift = GiftPurchase.find_by_global_id(gift_id)
    subject = "CoughDrop - Gift Created"
    subject = "CoughDrop - Bulk Purchase" if @gift.bulk_purchase?
    mail(to: @gift.settings['giver_email'], subject: subject)
  end
  
  def gift_redeemed(gift_id)
    @gift = GiftPurchase.find_by_global_id(gift_id)
    @recipient = @gift.receiver
    mail(to: @gift.settings['giver_email'], subject: "CoughDrop - Gift Redeemed")
  end
  
  def gift_seconds_added(gift_id)
    @gift = GiftPurchase.find_by_global_id(gift_id)
    @recipient = @gift.receiver
    mail_message(@recipient, "Gift Purchase Received")
  end
  
  def gift_updated(gift_id, action)
    @action_type = "Purchased"
    @action_type = "Redeemed" if action == 'redeem'
    @gift = GiftPurchase.find_by_global_id(gift_id)
    subject = "CoughDrop - Gift #{@action_type}"
    subject = "CoughDrop - Bulk Purchase" if @gift.bulk_purchase?
    if ENV['NEW_REGISTRATION_EMAIL']
      mail(to: ENV['NEW_REGISTRATION_EMAIL'], subject: subject)
    end
  end
end
