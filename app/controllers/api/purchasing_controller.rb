class Api::PurchasingController < ApplicationController
  def event
    res = Purchasing.subscription_event(request)
    render json: res[:data], :status => res[:status]
  end
  
  def purchase_gift
    return api_error 400, {error: "invalid purchase token"} unless params['token'] && params['token']['id']
    token = params['token']
    user_id = @api_user && @api_user.global_id
    progress = Progress.schedule(GiftPurchase, :process_subscription_token, token.to_unsafe_h, {'type' => params['type'], 'code' => params['code'], 'email' => params['email'], 'user_id' => user_id})
    render json: JsonApi::Progress.as_json(progress, :wrapper => true)
  end
end