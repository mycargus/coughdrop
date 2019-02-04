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
    end
    self.data['image_url'] ||= "https://s3.amazonaws.com/opensymbols/libraries/noun-project/Person-08e6d794b0.svg"
    self.data['show_user'] ||= false
    true
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
    return false unless sharer
    if params['supervisor_id']
      if sharer.supervisor_user_ids.include?(params['supervisor_id'])
        sup = User.find_by_path(params['supervisor_id'])
        return false unless sup
        self.schedule(:deliver_to, {'user_id' => sup.global_id, 'sharer_id' => sharer.global_id})
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
    if args['email']
      UserMailer.schedule_delivery(:utterance_share, {
        'subject' => subject,
        'message' => text,
        'sharer_id' => sharer.global_id,
        'to' => args['email']
      })
      return true
    elsif args['user_id']
      user = User.find_by_path(args['user_id'])
      if user
        notify('utterance_shared', {
          'sharer' => {'user_name' => sharer.user_name, 'user_id' => sharer.global_id},
          'user_id' => user.global_id,
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
    self.data['button_list'].each do |button|
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
