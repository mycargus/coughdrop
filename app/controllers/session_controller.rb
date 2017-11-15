class SessionController < ApplicationController
  before_action :require_api_token, :only => [:oauth_logout]
  
  def oauth
    error = nil
    response.headers.except! 'X-Frame-Options'
    key = DeveloperKey.find_by(:key => params['client_id'])
    if !key
      error = 'invalid_key'
    end
    if key && !key.valid_uri?(params['redirect_uri'])
      error = 'bad_redirect_uri'
    end
    @app_name = (key && key.name) || "the application"
    @app_icon = (key && key.icon_url) || "https://s3.amazonaws.com/opensymbols/libraries/arasaac/friends_3.png"
    if error
      @error = error
      render #:status => 400
    else
      scope = params['scope'] || ''
      scope = scope.sub(/full/, '')
      config = {
        'scope' => scope,
        'redirect_uri' => params['redirect_uri'] || key.redirect_uri,
        'device_key' => params['device_key'],
        'device_name' => params['device_name'],
        'app_name' => @app_name,
        'app_icon' => @app_icon
      }
      @code = GoSecure.nonce('oauth_code')
      RedisInit.default.setex("oauth_#{@code}", 1.hour.from_now.to_i, config.to_json)
      # render login page
      render
    end
  end
  
  def oauth_login
    error = nil
    user = nil
    response.headers.except! 'X-Frame-Options'
    config = JSON.parse(RedisInit.default.get("oauth_#{params['code']}")) rescue nil
    if !config
      error = 'code_not_found'
    else
      paramified_redirect = config['redirect_uri'] + (config['redirect_uri'].match(/\?/) ? '&' : '?')
      if params['reject']
        if config['redirect_uri'] == DeveloperKey.oob_uri
          redirect_to oauth_local_url(:error => 'access_denied')
        else
          redirect_to paramified_redirect + "error=access_denied"
        end
        return
      end
      user = User.find_for_login(params['username'])
      if user && params['approve_token']
        id = params['approve_token'].split(/~/)[0]
        device = Device.find_by_global_id(id)
        if !device || !device.valid_token?(params['approve_token']) || !device.permission_scopes.include?('full')
          error = 'invalid_token'
        end
      elsif !user || !user.valid_password?(params['password'])
        error = 'invalid_login'
      end
    end
    if error
      @app_name = (config && config['app_name']) || 'the application'
      @app_icon = (config && config['app_icon']) || "https://s3.amazonaws.com/opensymbols/libraries/arasaac/friends_3.png"
      @code = params['code']
      @error = error
      render :oauth, :status => 400
    else
      config['user_id'] = user.id.to_s
      RedisInit.default.setex("oauth_#{params['code']}", 1.hour.from_now.to_i, config.to_json)
      if config['redirect_uri'] == DeveloperKey.oob_uri
        redirect_to oauth_local_url(:code => params['code'])
      else
        redirect_to paramified_redirect + "code=#{params['code']}"
      end
    end
  end
  
  def oauth_token
    key = DeveloperKey.find_by(:key => params['client_id'])
    error = nil
    if !key
      error = 'invalid_key'
    elsif key.secret != params['client_secret']
      error = 'invalid_secret'
    end
    
    config = JSON.parse(RedisInit.default.get("oauth_#{params['code']}")) rescue nil
    if !error
      if !config
        error = 'code_not_found'
      elsif !config['user_id']
        error = 'token_not_ready'
      end
    end
    
    if error
      api_error 400, {error: error}
    else
      RedisInit.default.del("oauth_#{params['code']}")
      device = Device.find_or_create_by(:user_id => config['user_id'], :developer_key_id => key.id, :device_key => config['device_key'])
      device.settings['name'] = config['device_name']
      device.settings['name'] += device.id.to_s if device.settings['name'] == 'browser'
      device.settings['name'] ||= (key.name || "Token") + " account"
      if ['read_profile'].include?(config['scope'])
        device.settings['permission_scopes'] = [config['scope']]
      end
      device.generate_token!
      render json: JsonApi::Token.as_json(device.user, device).to_json
    end
  end
  
  def oauth_logout
    @api_device.logout!
    render json: {logout: true}.to_json
  end
  
  def oauth_local
    response.headers.except! 'X-Frame-Options'
  end
  
  def token
    set_browser_token_header
    if params['grant_type'] == 'password'
      pending_u = User.find_for_login(params['username'])
      u = nil
#      if params['client_id'] == 'browser' && GoSecure.valid_browser_token?(params['client_secret'])
        u = pending_u
#      else
#        return api_erorr 400, { error: "Invalid client secret" }
#      end
      if u && u.valid_password?(params['password'])
        # generated based on request headers
        # TODO: should also have some kind of developer key for tracking
        device_key = request.headers['X-Device-Id'] || params['device_id'] || 'default'
        
        d = Device.find_or_create_by(:user_id => u.id, :developer_key_id => 0, :device_key => device_key)
        d.settings['ip_address'] = request.remote_ip
        d.settings['user_agent'] = request.headers['User-Agent']
        d.settings['mobile'] = params['mobile'] == 'true'
        d.settings['browserless'] = params['browserless']
        d.generate_token!(!!params['long_token'])
        # find or create a device based on the request information
        # some devices (i.e. generic browser) are allowed multiple
        # tokens, so the token 
        render json: JsonApi::Token.as_json(u, d).to_json
      else
        old_key = OldKey.find_by(:type => 'user', :key => params['username'])
        user = old_key && old_key.record
        if user && user.valid_password?(params['password'])
          api_error 400, { error: "User name was changed", user_name: user.user_name}
        else
          api_error 400, { error: "Invalid authentication attempt" }
        end
      end
    else
      api_error 400, { error: "Invalid authentication approach" }
    end
  end
  
  def token_check
    set_browser_token_header
    if @api_user
      valid = @api_device.valid_token?(params['access_token'], request.headers['X-CoughDrop-Version'])
      render json: {
        authenticated: valid, 
        user_name: @api_user.user_name, 
        user_id: @api_user.global_id,
        avatar_image_url: (valid ? @api_user.generated_avatar_url : nil),
        scopes: @api_device && @api_device.permission_scopes,
        sale: ENV['CURRENT_SALE'],
        global_integrations: UserIntegration.global_integrations.keys
      }.to_json
    else
      render json: {
        authenticated: false, 
        sale: ENV['CURRENT_SALE'],
        global_integrations: UserIntegration.global_integrations.keys
      }.to_json
    end
  end
end
