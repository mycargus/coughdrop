class ApplicationController < ActionController::Base
  before_action :set_host
  before_action :check_api_token
  before_action :replace_helper_params
  before_action :set_paper_trail_whodunnit
  after_action :log_api_call
  before_bugsnag_notify :add_user_info_to_bugsnag
  
  # TODO: do we need a cache buster? Not for ember renders obviously, but for APIs?
  def set_host
    JsonApi::Json.set_host("#{request.protocol}#{request.host_with_port}")
  end
  
  def log_api_call
    time = @time ? (Time.now - @time) : nil
    ApiCall.log(@token, @api_user, request, response, time)
    true
  end
  
  def add_user_info_to_bugsnag(report)
    report.user = {
      id: GoSecure.sha512(request.remote_ip, 'user_ip')
    }
  end
  
  def check_api_token
    return true unless request.path.match(/^\/api/) || request.path.match(/^\/oauth2/) || params['check_token'] || request.headers['Check-Token']
#     if request.path.match(/^\/api/)
#       headers['Access-Control-Allow-Origin'] = '*'
#       headers['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS'
#       headers['Access-Control-Max-Age'] = "1728000"      
#     end
    @time = Time.now
    Time.zone = nil
    token = params['access_token']
    PaperTrail.whodunnit = nil
    if !token && request.headers['Authorization']
      match = request.headers['Authorization'].match(/^Bearer ([\w\-_\~]+)$/)
      token = match[1] if match
    end
    @token = token
    if token
      id = token.split(/~/)[0]
      @api_device = Device.find_by_global_id(id)
      if !['/api/v1/token_check'].include?(request.path)
        if !@api_device || !@api_device.valid_token?(token, request.headers['X-CoughDrop-Version'])
          @api_device = nil
          set_browser_token_header
          api_error 400, {error: (@api_device ? "Expired token" : "Invalid token"), token: token, invalid_token: true}
          return false
        elsif @api_device && @api_device.disabled?
          @api_device = nil
          set_browser_token_header
          api_error 400, {error: 'Disabled token', token: token}
          return false
        end
      end
      @api_user = @api_device && @api_device.user
      if @api_user && @api_device
        @api_user.permission_scopes_device = @api_device
      end
      # TODO: timezone user setting
      Time.zone = "Mountain Time (US & Canada)"
      PaperTrail.whodunnit = user_for_paper_trail

      as_user = params['as_user_id'] || request.headers['X-As-User-Id']
      if @api_user && as_user
        @linked_user = User.find_by_path(as_user)
        admin = Organization.admin
        if admin && admin.manager?(@api_user) && @linked_user
          @true_user = @api_user
          @api_user = @linked_user
          PaperTrail.whodunnit = "user:#{@true_user.global_id}:as:#{@api_user.global_id}"
        else
          api_error 400, {error: "Invalid masquerade attempt", token: token, user_id: as_user}
        end
      end
      
    end
  end
  
  def user_for_paper_trail
    @api_user ? "user:#{@api_user.global_id}.#{params['controller']}.#{params['action']}" : "unauthenticated:#{request.remote_ip}.#{params['controller']}.#{params['action']}"
  end
  
  def replace_helper_params
    params.each do |key, val|
      if @api_user && (key == 'id' || key.match(/_id$/)) && val == 'self'
        params[key] = @api_user.global_id
      end
      if @api_user && (key == 'id' || key.match(/_id$/)) && val == 'my_org' && Organization.manager?(@api_user)
        org = @api_user.organization_hash.select{|o| o['type'] == 'manager' }.sort_by{|o| o['added'] || Time.now.iso8601 }[0]
        params[key] = org['id'] if org
      end
    end
  end
  
  def require_api_token
    if !@api_user
      if !@token || @token.length == 0
        api_error 400, {error: "Access token required for this endpoint: missing token"}
      elsif !@api_device
        api_error 400, {error: "Access token required for this endpoint: couldn't find matching device"}
      else
        api_error 400, {error: "Access token required for this endpoint: couldn't find matching user"}
      end
    end
  end
  
  def allowed?(obj, permission)
    scopes = ['*']
    if @api_user && @api_device
      @api_user.permission_scopes_device = @api_device
      scopes = @api_user.permission_scopes || []
    end
    if !obj || !obj.allows?(@api_user, permission, scopes)
      res = {error: "Not authorized", unauthorized: true}
      if permission.instance_variable_get('@scope_rejected')
        res[:scope_limited] = true
      end
      api_error 400, res
      false
    else
      true
    end
  end
  
  def api_error(status_code, hash)
    hash[:status] = status_code
    if hash[:error].blank? && hash['error'].blank?
      hash[:error] = "unspecified error"
    end
    cachey = request.headers['X-Has-AppCache'] || params['nocache']
    render json: hash.to_json, status: (cachey ? 200 : status_code)
  end
  
  def exists?(obj, ref_id=nil)
    if !obj
      res = {error: "Record not found"}
      res[:id] = ref_id if ref_id
      api_error 404, res
      false
    else
      true
    end
  end

  def set_browser_token_header
    response.headers['BROWSER_TOKEN'] = GoSecure.browser_token
  end
end
