class ButtonSound < ActiveRecord::Base
  include Processable
  include Permissions
  include Uploadable
  include MediaObject
  include Async
  include GlobalId
  include SecureSerialize
  protect_global_id
  belongs_to :board
  has_many :board_button_sounds
  belongs_to :user
  before_save :generate_defaults
  after_save :schedule_transcription
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
  
  def schedule_transcription(frd=false)
    if self.url && !self.settings['transcription'] && self.settings['secondary_output']
      if frd
        ref = self.settings['secondary_output']
        # download the wav file
        # pass it to google cloud recognition async
        # (wav file, 44100Hz, linear PCM)
        # wait for a result
        # on success, set transcription (including confidence) and delete the wav file from S3
        # on error, increment failed attempts and give up after 3
        # https://cloud.google.com/speech/reference/rest/
      else
        # if too many failed attempts, don't schedule again
        # if last attempt was too recent, don't schedule again
        schedule_once(:schedule_transcription, true)
      end
    end
  end
  
  def process_params(params, non_user_params)
    raise "user required as sound author" unless self.user_id || non_user_params[:user]
    self.user ||= non_user_params[:user] if non_user_params[:user]
    @download_url = false if non_user_params[:download] == false
    self.settings ||= {}
    process_url(params['url'], non_user_params) if params['url']
    self.settings['content_type'] = params['content_type'] if params['content_type']
    self.settings['duration'] = params['duration'].to_i if params['duration']
    self.settings['name'] = params['name'] if params['name']
    self.settings['transcription'] = params['transcriptions'] if params['transcription']
    # TODO: raise a stink if content_type or duration are not provided
    process_license(params['license']) if params['license']
    self.settings['protected'] = params['protected'] if params['protected'] != nil
    self.settings['protected'] = params['ext_coughdrop_protected'] if params['ext_coughdrop_protected'] != nil
    self.settings['suggestion'] = params['suggestion'] if params['suggestion']
    self.public = params['public'] if params['public'] != nil
    true
  end
end
