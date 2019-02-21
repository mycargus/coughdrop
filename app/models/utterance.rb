class Utterance < ActiveRecord::Base
  include GlobalId
  include Processable
  include Permissions
  include MetaRecord
  include SecureSerialize
  include Async
  include Notifier
  protect_global_id
  replicated_model  
  
  belongs_to :user
  before_save :generate_defaults
  after_save :generate_preview_later
  
  add_permissions('view', ['*']) { true }
  add_permissions('view', 'edit') {|user| self.user_id == user.id || (self.user && self.user.allows?(user, 'edit')) }
#  has_paper_trail :only => [:data, :user_id]
  secure_serialize :data

  def generate_defaults
    self.data ||= {}
    if self.data['button_list']
      if !self.data['image_url']
        self.data['image_url'] ||= self.data['button_list'].map{|b| b['image'] }.compact.first
        self.data['default_image_url'] = true
      end
      if !self.data['sentence'] || self.data['sentence'].blank?
        self.data['sentence'] = self.data['button_list'].map{|b| b['vocalization'] || b['label'] }.compact.join(' ')
      end
    end
    tmp_nonce = nil
    attempts = 0
    while !self.reply_nonce && (!tmp_nonce || Utterance.find_by(reply_nonce: tmp_nonce))
      tmp_nonce = GoSecure.nonce('utterance_reply_code')[0, 10]
      attempts += 1
      raise "can't generate nonce" if attempts > 10
    end
    self.reply_nonce = tmp_nonce if tmp_nonce
    self.data['image_url'] ||= "https://s3.amazonaws.com/opensymbols/libraries/noun-project/Person-08e6d794b0.svg"
    self.data['show_user'] ||= false
    true
  end

  def self.clear_old_nonces
    Utterance.where(['reply_nonce IS NOT NULL AND created_at < ?', 14.days.ago]).update_all(reply_nonce: nil)
  end
  
  def generate_preview
    url = SentencePic.generate(self)
    self.data ||= {}
    self.data['large_image_url_attempted'] = true
    self.data['large_image_url'] = url
    if self.data['default_image_url']
      self.data['image_url'] = self.data['large_image_url']
    end
    self.save
  end
  
  def generate_preview_later
    if self.data && !self.data['large_image_url_attempted']
      self.schedule(:generate_preview)
    end
    true
  end
  
  def share_with(params, sharer)
    sharer = User.find_by_path(sharer) if sharer.is_a?(String)
    return false unless sharer
    user_id = params['user_id'] || params['supervisor_id']
    if user_id
      message = params['message'] || params['sentence'] || self.data['sentence']
      if (sharer.supervised_user_ids + sharer.supervisor_user_ids).include?(user_id)
        sup = User.find_by_path(user_id)
        return false unless sup
        if sharer.supervisor_user_ids.include?(user_id)
          # message from a communicator to a supervisor
          self.schedule(:deliver_to, {'user_id' => sup.global_id, 'sharer_id' => sharer.global_id})
        elsif sharer.supervised_user_ids.include?(user_id)
          # message from a supervisor to a communicator
          return false unless LogSession.message({
            recipient: sup,
            sender: sharer,
            device: @api_device,
            message: message,
            reply_id: params['reply_id']
          })
        end
        return {to: sup.global_id, from: sharer.global_id, type: 'utterance'}
      end
    elsif params['email']
      self.schedule(:deliver_to, {
        'sharer_id' => sharer.global_id,
        'email' => params['email'],
        'subject' => params['subject'] || params['message'] || params['sentence'],
        'message' => params['message'] || params['sentence']
      })
      return {to: params['email'], from: sharer.global_id, type: 'email'}
    end
    return false
  end
  
  def deliver_to(args)
    sharer = User.find_by_path(args['sharer_id'])
    raise "sharer required" unless sharer
    text = args['message'] || self.data['sentence']
    subject = args['subject'] || self.data['sentence']
    reply_url = "#{JsonApi::Json.current_host}/u/#{self.reply_nonce}"
    if args['email']
      UserMailer.schedule_delivery(:utterance_share, {
        'subject' => subject,
        'message' => text,
        'sharer_id' => sharer.global_id,
        'utterance_id' => self.global_id,
        'to' => args['email'],
        'reply_url' => reply_url
      })
      return true
    elsif args['user_id']
      user = User.find_by_path(args['user_id'])
      if user
        notify('utterance_shared', {
          'sharer' => {'user_name' => sharer.user_name, 'user_id' => sharer.global_id},
          'user_id' => user.global_id,
          'utterance_id' => self.global_id,
          'reply_url' => reply_url,
          'text' => text
        })
      end
      return true
    end
    raise "share failed"
  end
  
  def additional_listeners(type, args)
    if type == 'utterance_shared'
      u = User.find_by_global_id(args['user_id'])
      res = []
      res << u.record_code if u
      res
    end
  end
  
  def process_params(params, non_user_params)
    raise "user required" unless self.user || non_user_params[:user]
    self.user = non_user_params[:user] if non_user_params[:user]
    self.data ||= {}
    self.data['button_list'] = params['button_list'] if params['button_list'] # TODO: process this for real
    (self.data['button_list'] || []).each do |button|
      # Don't use local URLs for saving the utterance to show to others
      if button['original_image'] && !button['image'].match(/^http/)
        button['image'] = button['original_image']
        button.delete('original_image')
      end
    end
    self.data['sentence'] = params['sentence'] if params['sentence'] # TODO: process this for real
    if params['image_url'] && params['image_url'] != self.data['image_url']
      self.data['image_url'] = params['image_url'] 
      self.data['default_image_url'] = false
    end
    self.data['show_user'] = process_boolean(params['show_user']) if params['show_user']
    return true
  end
end
