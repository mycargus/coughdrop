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
    if params['sound']['user_id']
      user = User.find_by_path(params['sound']['user_id'])
      return unless exists?(user, params['sound']['user_id'])
      return unless allowed?(user, 'supervise')
    end
    sound = ButtonSound.process_new(params['sound'], {:user => user, :remote_upload_possible => true})
    if !sound || sound.errored?
      api_error(400, {error: "sound creation failed", errors: sound && sound.processing_errors})
    else
      render json: JsonApi::Sound.as_json(sound, :wrapper => true, :permissions => @api_user).to_json
    end
  end
  
  def import
    if params['url']
      progress = Progress.schedule(ButtonSound, :import_for, @api_user.global_id, params['url'])
      render json: JsonApi::Progress.as_json(progress, :wrapper => true).to_json
    else
      remote_path = "imports/sounds/#{@api_user.global_id}/upload-#{GoSecure.nonce('filename')}.zip"
      content_type = "application/zip"
      params = Uploader.remote_upload_params(remote_path, content_type)
      url = params[:upload_url] + remote_path
      params[:success_url] = "/api/v1/sounds/imports?url=#{CGI.escape(url)}"
      render json: {'remote_upload' => params}.to_json
    end
  end
  
  def show
    sound = ButtonSound.find_by_path(params['id'])
    return unless exists?(sound, params['id'])
    return unless allowed?(sound, 'view')
    render json: JsonApi::Sound.as_json(sound, :wrapper => true, :permissions => @api_user).to_json
  end
  
  def update
    sound = ButtonSound.find_by_path(params['id'])
    return unless exists?(sound, params['id'])
    return unless allowed?(sound, 'edit')
    if sound.process(params['sound'])
      render json: JsonApi::Sound.as_json(sound, :wrapper => true, :permissions => @api_user).to_json
    else
      api_error(400, {error: "sound update failed", errors: sound.processing_errors})
    end
  end
  
  def destroy
    sound = ButtonSound.find_by_path(params['id'])
    return unless exists?(sound, params['id'])
    return unless allowed?(sound, 'edit')
    if sound.destroy
      render json: JsonApi::Sound.as_json(sound, :wrapper => true, :permissions => @api_user).to_json
    else
      api_error(400, {error: "sound deletion failed"})
    end
    # delete the sound, any board connections, and remove it from s3
  end
end
