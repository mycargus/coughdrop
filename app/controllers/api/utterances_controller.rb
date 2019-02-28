class Api::UtterancesController < ApplicationController
  before_action :require_api_token, :except => [:show, :reply]
  
  def show
    utterance_id, reply_code = params['id'].split(/x/)
    utterance = Utterance.find_by_global_id(utterance_id)
    return unless exists?(utterance, utterance_id)
    return unless allowed?(utterance, 'view')

    if reply_code
      match = reply_code.match(/^([0-9a-f]+)([A-Z]+)$/)
      reply_nonce = match && match[1]
      if !utterance.reply_nonce || utterance.reply_nonce != reply_nonce
        reply_code = nil
      end
    end
    if !reply_code && utterance.data['private_only']
      return allowed?(utterance, 'never_allow')
    end

    render json: JsonApi::Utterance.as_json(utterance, :wrapper => true, :permissions => @api_user, :reply_code => reply_code).to_json
  end
  
  def create
    user = @api_user
    if params['utterance'] && params['utterance']['user_id']
      user = User.find_by_path(params['utterance']['user_id'])
      return unless exists?(user, params['utterance']['user_id'])
      return unless allowed?(user, 'supervise')
    end
    utterance = Utterance.process_new(params['utterance'], {:user => user})
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
    if params['user_id'] && !sharer.premium?
      return allowed?(user, 'premium_access')      
    end
    res = utterance.share_with(params, sharer, @api_user.global_id)
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

  def reply
    utterance_id, reply_code = params['utterance_id'].split(/x/)
    utterance = Utterance.find_by_global_id(utterance_id)
    return unless exists?(utterance, utterance_id)
    return unless allowed?(utterance, 'view')

    reply_index = nil
    if reply_code
      match = reply_code.match(/^([0-9a-f]+)([A-Z]+)$/)
      reply_nonce = match && match[1]
      share_index = match[2]
      if utterance.reply_nonce && utterance.reply_nonce == reply_nonce
        reply_index = Utterance.from_alpha_code(share_index)
      end
    end
    if !reply_index || !(utterance.data['share_user_ids'] || {})[reply_index]
      return exists?(nil, reply_code)
    end

    #raise "for user contacts, ensure that the contact hash still exists"

    user_id = utterance.data['share_user_ids'][reply_index]
    sharer = User.find_by_path(user_id)
    return unless exists?(sharer, user_id)
    # this reply mechanism should only be used to reply to a communicator
    res = LogSession.message({
      recipient: utterance.user,
      sender: sharer,
      sender_id: user_id,
      notify: 'user_only',
      device: sharer.devices[0],
      message: params['message'],
      reply_id: utterance.global_id
    })
    render json: {sent: !!res, from: user_id, to: utterance.user.global_id}
  end
end
