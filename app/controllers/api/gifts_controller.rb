class Api::GiftsController < ApplicationController
  before_action :require_api_token, :except => [:show]
  # TODO: implement throttling to prevent brute force gift lookup

  def show
    gift = GiftPurchase.find_by_code(params['id'])
    return unless exists?(gift, params['id'])
    return unless allowed?(gift, 'view')
    render json: JsonApi::Gift.as_json(gift, :wrapper => true, :permissions => @api_user).to_json
  end
  
  def index
    return unless allowed?(@api_user, 'admin_support_actions')
    gifts = GiftPurchase.all.order('id DESC')
    render json: JsonApi::Gift.paginate(params, gifts)
  end
  
  def create
    return unless allowed?(@api_user, 'admin_support_actions')
    gift = GiftPurchase.process_new({
      'licenses' => params['gift']['licenses'],
      'amount' => params['gift']['amount'],
      'email' => params['gift']['email'],
      'organization' => params['gift']['organization'],
      'gift_name' => params['gift']['gift_name']
    }, {
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
    gift = GiftPurchase.find_by_code(params['gift_id'])
    return unless exists?(gift, params['gift_id'])
    gift.active = false
    gift.save
    render json: JsonApi::Gift.as_json(gift, :wrapper => true, :permissions => @api_user).to_json
  end
end
