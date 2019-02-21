class Api::UtterancesController < ApplicationController
  before_action :require_api_token, :except => [:show]
  
  def show
    utterance = Utterance.find_by_global_id(params['id'])
    return unless exists?(utterance)
    return unless allowed?(utterance, 'view')
    render json: JsonApi::Utterance.as_json(utterance, :wrapper => true, :permissions => @api_user).to_json
  end
  
  def create
    utterance = Utterance.process_new(params['utterance'], {:user => @api_user})
    if !utterance || utterance.errored?
      api_error(400, {error: "utterance creation failed", errors: utterance.processing_errors})
    else
      render json: JsonApi::Utterance.as_json(utterance, :wrapper => true, :permissions => @api_user).to_json
    end
  end
  
  def share
    utterance = Utterance.find_by_global_id(params['utterance_id'])
    return unless exists?(utterance)
    return unless allowed?(utterance, 'edit')
    sharer = @api_user
    if params['sharer_id'] && @api_user && params['sharer_id'] != @api_user.global_id
      user = User.find_by_path(params['sharer_id'])
      return unless exists?(user, params['sharer_id'])
      return unless allowed?(user, 'supervise')
      sharer = user
    end
    res = utterance.share_with(params, sharer, @api_user)
    if res
      render json: {shared: true, details: res}.to_json
    else
      api_error(400, {error: "utterance share failed"})
    end
  end

  def update
    utterance = Utterance.find_by_global_id(params['id'])
    return unless exists?(utterance)
    return unless allowed?(utterance, 'edit')
    if utterance.process(params['utterance'])
      render json: JsonApi::Utterance.as_json(utterance, :wrapper => true, :permissions => @api_user).to_json
    else
      api_error(400, {error: "utterance update failed", errors: utterance.processing_errors})
    end
  end
end
