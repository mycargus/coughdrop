class Api::GiftsController < ApplicationController
  before_action :require_api_token, :except => [:show]
  # TODO: implement throttling to prevent brute force gift lookup

  def show
    id, verifier = params['id'].split(/::/)
    gift = GiftPurchase.find_by_code(id.gsub(/x/, '&'))
    return unless exists?(gift, params['id'])
    return unless allowed?(gift, 'view')
    return allowed?(gift, 'never_allow') if id.length < 20 && verifier != gift.code_verifier
    render json: JsonApi::Gift.as_json(gift, :wrapper => true, :permissions => @api_user).to_json
  end
  
  def index
    return unless allowed?(@api_user, 'admin_support_actions')
    gifts = GiftPurchase.all.order('id DESC')
    render json: JsonApi::Gift.paginate(params, gifts)
  end
  
  def create
    return unless allowed?(@api_user, 'admin_support_actions')
    code = params['gift']['code']
    if code && GiftPurchase.find_by(code: code)
      api_error 400, {error: 'code is taken'}
      return
    end
    gift = GiftPurchase.process_new(
    params['gift'].slice('licenses', 'total_codes', 'amount', 
          'expires', 'limit', 'code', 'memo', 'email', 'organization', 
          'org_id', 'gift_type', 'gift_name', 'discount'), 
    {
      'giver' => @api_user,
      'email' => @api_user.settings['email'],
      'seconds' => params['gift']['seconds'].to_i
    })
    
    if gift.errored?
      api_error(400, {error: "gift creation failed", errors: gift && gift.processing_errors})
    else
      render json: JsonApi::Gift.as_json(gift, :wrapper => true, :permissions => @api_user).to_json
    end
  end
  
  def destroy
    return unless allowed?(@api_user, 'admin_support_actions')
    gift = GiftPurchase.find_by_code(params['id'].gsub(/x/, '&'))
    return unless exists?(gift, params['id'])
    gift.active = false
    gift.save
    render json: JsonApi::Gift.as_json(gift, :wrapper => true, :permissions => @api_user).to_json
  end
end
