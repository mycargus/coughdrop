class Api::SoundsController < ApplicationController
  include RemoteUploader
  before_action :require_api_token, :except => [:upload_success]

  def index
    user = User.find_by_path(params['user_id'])
    return unless exists?(user, params['user_id'])
    return unless allowed?(user, 'supervise')
    # TODO: sharding
    sounds = ButtonSound.where(:user_id => user.id).order('id DESC')
    render json: JsonApi::Sound.paginate(params, sounds)
  end
  
  def create
    user = @api_user
    if params['user_id']
      user = User.find_by_path(params['user_id'])
      return unless exists?(user, params['user_id'])
      return unless allowed?(user, 'supervise')
    end
    sound = ButtonSound.process_new(params['sound'], {:user => user, :remote_upload_possible => true})
    if !sound || sound.errored?
      api_error(400, {error: "sound creation failed", errors: sound && sound.processing_errors})
    else
      render json: JsonApi::Sound.as_json(sound, :wrapper => true, :permissions => @api_user).to_json
    end
  end
  
  def show
    sound = ButtonSound.find_by_path(params['id'])
    return unless exists?(sound)
    return unless allowed?(sound, 'view')
    render json: JsonApi::Sound.as_json(sound, :wrapper => true, :permissions => @api_user).to_json
  end
  
  def update
    sound = ButtonSound.find_by_path(params['id'])
    return unless exists?(sound)
    return unless allowed?(sound, 'view')
    if sound.process(params['sound'])
      render json: JsonApi::Sound.as_json(sound, :wrapper => true, :permissions => @api_user).to_json
    else
      api_error(400, {error: "sound update failed", errors: sound.processing_errors})
    end
  end
  
  def destroy
    api_error 400, {error: 'not enabled'}
    # delete the sound, any board connections, and remove it from s3
  end
end
