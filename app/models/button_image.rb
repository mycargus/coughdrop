class ButtonImage < ActiveRecord::Base
  include Processable
  include Permissions
  include Uploadable
  include Async
  include GlobalId
  include SecureSerialize
  protect_global_id
  belongs_to :board
  has_many :board_button_images
  belongs_to :user
  before_save :generate_defaults
  after_create :track_image_use_later
  replicated_model  

  has_paper_trail :on => [:destroy] #:only => [:settings, :board_id, :user_id, :public, :path, :url, :data]
  secure_serialize :settings
  
  add_permissions('view', ['*']) { true }
  add_permissions('view', 'edit') {|user| self.user_id == user.id || (self.user && self.user.allows?(user, 'edit')) }
  cache_permissions

  def generate_defaults
    self.settings ||= {}
    self.settings['license'] ||= {
      'type' => 'private'
    }
    self.public ||= false
    true
  end
  
  def protected?
    !!self.settings['protected']
  end
  
  def track_image_use_later
    schedule(:track_image_use)
    true
  end
  
  def track_image_use
    self.settings ||= {}
    # Only public boards call back to opensymbols, to prevent private user information leakage
    if !self.settings['suggestion'] && (self.settings['label'] || self.settings['search_term'])  && self.board && self.board.public
      ButtonImage.track_image_use({
        :search_term => self.settings['search_term'],
        :label => self.settings['label'],
        :suggestion => self.settings['suggestion'],
        :external_id => self.settings['external_id'],
        :user_id => self.user.global_id
      })
    end
  end
  
  def self.track_image_use(options)
    options = options.with_indifferent_access
    label = options[:search_term] || options[:label]
    if label && options[:external_id] && ENV['OPENSYMBOLS_TOKEN'] && options[:user_id]
      id = options[:external_id]
      # TODO: don't hard-code to this URL
      # TODO: add a timeout for this, or it can hang for a very long time...
      Typhoeus.post("https://opensymbols.herokuapp.com/api/v1/symbols/#{id}/use", body: {
        access_token: ENV['OPENSYMBOLS_TOKEN'],
        user_id: Security.sha512(options[:user_id], 'global_user_id')[0, 10],
        keyword: label
      })
    end
  end
  
  def self.track_images(images_to_track)
    images_to_track.each do |img|
      self.track_image_use(img)
    end
  end
  
  def process_params(params, non_user_params)
    raise "user required as image author" unless self.user_id || non_user_params[:user]
    self.user ||= non_user_params[:user] if non_user_params[:user]
    self.settings ||= {}
    process_url(params['url'], non_user_params) if params['url']
    self.settings['content_type'] = params['content_type'] if params['content_type']
    self.settings['width'] = params['width'].to_i if params['width']
    self.settings['height'] = params['height'].to_i if params['height']
    # TODO: when cleaning up orphan images, don't delete avatar images
    self.settings['avatar'] = !!params['avatar'] if params['avatar'] != nil
    self.settings['badge'] = !!params['badge'] if params['badge'] != nil
    # TODO: raise a stink if content_type, width or height are not provided
    process_license(params['license']) if params['license']
    self.settings['protected'] = params['protected'] if params['protected'] != nil
    self.settings['protected'] = params['ext_coughdrop_protected'] if params['ext_coughdrop_protected'] != nil
    self.settings['finding_user_name'] = params['finding_user_name'] if params['finding_user_name']
    self.settings['suggestion'] = params['suggestion'] if params['suggestion']
    self.settings['search_term'] = params['search_term'] if params['search_term']
    self.settings['external_id'] = params['external_id'] if params['external_id']
    self.public = params['public'] if params['public'] != nil
    true
  end
end
