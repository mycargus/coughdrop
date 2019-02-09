class Api::TagsController < ApplicationController
  before_action :require_api_token

  def index
    user = @api_user
    if params['user_id']
      user = User.find_by_path(params['user_id'])
      return unless exists?(user, params['user_id'])
      return unless allowed?(user, 'supervise')
    end
    @tags = NfcTag.where(user_id: user.id)
    
    render json: JsonApi::Tag.paginate(params, @tags)
  end

  def create
    return unless allowed?(@api_user, 'supervise')

    @tag = NfcTag.process_new(params['tag'], {:user => @api_user})
    if @tag.errored?
      api_Error(400, {error: 'tag creation failed', errors: @tag.processing_errors})
    else
      render json: JsonApi::Tag.as_json(@tag, :wrapper => true, :permissions => @api_user).to_json
    end
  end

  def show
    @tag = NfcTag.find_by_global_id(params['id'])
    if !@tag
      # When searching by tag_id, first look for one by the
      # user, then look for the most-recent public one
      tags = NfcTag.where(tag_id: params['id'])
      if tags.length > 0
        @tag = tags.where(user_id: @api_user.id).order('id DESC')[0]
        @tag ||= tags.where(public: true).order('id DESC')[0]
      end
    end
    return unless exists?(@tag, params['id'])
    if !@tag.public
      return unless allowed?(@tag.user, 'supervise')
    end
    @tag.touch if @tag.updated_at < 2.weeks.ago
    render json: JsonApi::Tag.as_json(@tag, :wrapper => true, :permissions => @api_user).to_json
  end

  def update
    @tag = NfcTag.find_by_global_id(params['id'])
    return unless exists?(@tag, params['id'])
    return unless allowed?(@tag.user, 'supervise')
    if @tag.process(params['tag'], {user: @api_user})
      render json: JsonApi::Tag.as_json(@tag, :wrapper => true, :permissions => @api_user)
    else
      api_error(400, {error: "tag update failed", errors: @tag.processing_errors})
    end
  end
  
  def destroy
    @tag = NfcTag.find_by_global_id(params['id'])
    
    return unless exists?(@tag, params['id'])
    return unless allowed?(@tag.user, 'supervise')
    @tag.destroy

    render json: JsonApi::Tag.as_json(@tag, :wrapper => true, :permissions => @api_user).to_json
  end
end
