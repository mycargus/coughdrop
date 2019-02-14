class NfcTag < ApplicationRecord
  include SecureSerialize
  include GlobalId
  include Async
  include Processable

  protect_global_id

  before_save :generate_defaults
  after_save :attach_to_user
  secure_serialize :data
  belongs_to :user

  def generate_defaults
    self.data ||= {}
    self.nonce ||= GoSecure.nonce('nfc_tag_secure_nonce')[0, 6]
    self.public ||= false
    self.has_content = !!(self.data['button'] || !self.data['label'].blank?)
    true
  end

  def attach_to_user(frd=false)
    if !frd
      schedule(:attach_to_user, true)
      return true
    end
    u = self.user
    if self.has_content
      u.settings['preferences']['tag_ids'] ||= []
      u.settings['preferences']['tag_ids'].push(self.global_id)
      u.save
    end
  end

  def process_params(params, non_user_params)
    raise 'user required' unless non_user_params['user']
    self.generate_defaults
    
    self.data['button'] = params['button'] if params['button']
    self.data['label'] = params['label'] if params['label']
    self.tag_id = params['tag_id'] if params['tag_id']
    self.public = params['public'] if params['public'] != nil
    self.user ||= non_user_params['user']
    true
  end

  # TODO: remove old tags if they are no longer accessible:
  # - they are private and there is a newer one for the same user
  # - has_content=false and more than 1 month old
  # TODO: track the last time they are downloaded/used and flush eventually
end
