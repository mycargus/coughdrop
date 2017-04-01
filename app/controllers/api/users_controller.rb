class Api::UsersController < ApplicationController
  extend ::NewRelic::Agent::MethodTracer

  before_action :require_api_token, :except => [:update, :show, :create, :confirm_registration, :forgot_password, :password_reset, :protected_image, :subscribe]
  def show
    user = User.find_by_path(params['id'])
    user_device = @api_user == user && @api_device
    allowed = false
    return unless exists?(user, params['id'])
    if user.registration_code && params['confirmation'] == user.registration_code
      allowed = true
      @include_subscription = true
    end
    self.class.trace_execution_scoped(['user/permission_check']) do
      allowed ||= allowed?(user, 'view_existence')
    end
    return unless allowed
    json = {}
    self.class.trace_execution_scoped(['user/json_render']) do
      json = JsonApi::User.as_json(user, :wrapper => true, :permissions => @api_user, :device => user_device, :include_subscription => @include_subscription)
    end
    
    render json: json.to_json
  end
  
  def sync_stamp
    user = User.find_by_path(params['user_id'])
    return unless exists?(user, params['user_id'])
    if user != @api_user
      return unless allowed?(user, 'never_allow')
    end
    render json: {sync_stamp: user.updated_at.utc.iso8601, badges_updated_at: (user.badges_updated_at || user.created_at).utc.iso8601 }
  end
  
  def places
    user = User.find_by_path(params['user_id'])
    return unless exists?(user, params['user_id'])
    return unless allowed?(user, 'supervise')
    render json: Geolocation.find_places(params['latitude'], params['longitude'])
  end
  
  def index
    if !Organization.admin_manager?(@api_user)
      return api_error 400, {error: 'admins only'}
    end
    if !params['q']
      return api_error 400, {error: 'q parameter required'}
    end
    users = []
    if params['q'].match(/@/)
      users = User.find_by_email(params['q'])
    else
      users = User.where(:user_name => params['q'])
      users = [User.find_by_global_id(params['q'])].compact if users.count == 0
      if users.count == 0
        users = User.where(["user_name ILIKE ?", "%#{params['q']}%"]).order('user_name')
      end
    end
    render json: JsonApi::User.paginate(params, users)
  end
  
  def update
    user = User.find_by_path(params['id'])
    user_device = @api_user == user && @api_device
    return unless exists?(user)
    options = {}
    if params['reset_token'] && user.valid_reset_token?(params['reset_token'])
      params['user'] ||= {}
      params['user'] = params['user'].slice('password')
      options[:allow_password_change] = true
      user.used_reset_token!(params['reset_token'])
    elsif params['reset_token'] == 'admin' && user.allows?(@api_user, 'support_actions')
      params['user'] ||= {}
      params['user'] = params['user'].slice('password')
      options[:allow_password_change] = true
      user.used_reset_token!(params['reset_token'])
    elsif user.allows?(@api_user, 'manage_supervision') && !user.allows?(@api_user, 'edit')
      params['user'] ||= {}
      params['user'] = params['user'].slice('supervisor_key')
    else
      return unless allowed?(user, 'edit')
    end
    options['device'] = @api_device if user == @api_user
    options['updater'] = @api_user
      
    if user.process(params['user'], options)
      render json: JsonApi::User.as_json(user, :wrapper => true, :permissions => @api_user, :device => user_device).to_json
    else
      api_error 400, {error: 'update failed', errors: user.processing_errors}
    end
  end
  
  def create
    user = User.process_new(params['user'], {:pending => true})
    if !user || user.errored?
      return api_error(400, {error: "user creation failed", errors: user && user.processing_errors})
    end
    UserMailer.schedule_delivery(:confirm_registration, user.global_id)
    UserMailer.schedule_delivery(:new_user_registration, user.global_id)
    ExternalTracker.track_new_user(user)

    d = Device.find_or_create_by(:user_id => user.id, :device_key => 'default', :developer_key_id => 0)
    d.settings['ip_address'] = request.remote_ip
    d.settings['user_agent'] = request.headers['User-Agent']
    
    d.generate_token!

    res = JsonApi::User.as_json(user, :wrapper => true, :permissions => @api_user || user)
    res['meta'] = JsonApi::Token.as_json(user, d)
    render json: res.to_json
  end
  
  def claim_voice
    user = User.find_by_path(params['user_id'])
    return unless exists?(user, params['user_id'])
    return unless allowed?(user, 'edit')
    if user.add_premium_voice(params['voice_id'], params['system'])
      res = {voice_added: true, voice_id: params['voice_id']}
      if params['voice_url']
        res[:download_url] = Uploader.signed_download_url(params['voice_url'])
      end
      render json: res.to_json
    else
      api_error(400, {error: "no more voices available"})
    end
  end
  
  def activate_button
    user = User.find_by_path(params['user_id'])
    return unless exists?(user, params['user_id'])
    return unless allowed?(user, 'supervise')
    board = Board.find_by_path(params['board_id'])
    return unless exists?(board, params['board_id'])
    return unless allowed?(board, 'view')
    button = params['button_id'] && board.settings['buttons'].detect{|b| b['id'].to_s == params['button_id'].to_s }
    if !button
      return api_error(400, {error: 'button not found'})
    elsif !button['integration'] || !button['integration']['user_integration_id']
      return api_error(400, {error: 'button integration not configured'})
    end
    associated_user = nil
    if params['associated_user_id']
      supervisee = User.find_by_path(params['associated_user_id'])
      if supervisee && supervisee.allows?(user, 'supervise')
        associated_user = supervisee
      end
    end
    progress = Progress.schedule(board, :notify, 'button_action', {
      'user_id' => user.global_id,
      'immediate' => true,
      'associated_user_id' => (associated_user && associated_user.global_id),
      'button_id' => params['button_id']
    })
    render json: JsonApi::Progress.as_json(progress, :wrapper => true)
  end
  
  def rename
    user = User.find_by_path(params['user_id'])
    return unless exists?(user)
    return unless allowed?(user, 'edit')
    if params['new_key'] && params['old_key'] == user.user_name && user.rename_to(params['new_key'])
      render json: {rename: true, key: params['new_key']}.to_json
    else
      api_error(400, {error: "user rename failed", key: params['key'], collision: user.collision_error?})
    end
  end
  
  def flush_logs
    user = User.find_by_path(params['user_id'])
    return unless allowed?(user, 'delete')
    return api_error(400, {'flushed' => 'false'}) unless user.user_name == params['user_name'] && user.global_id == params['user_id']
    progress = Progress.schedule(Flusher, :flush_user_logs, user.global_id, user.user_name)
    render json: JsonApi::Progress.as_json(progress, :wrapper => true)
  end
  
  def flush_user
    user = User.find_by_path(params['user_id'])
    return unless allowed?(user, 'delete')
    return api_error(400, {'flushed' => 'false'}) unless user.user_name == params['user_name'] && user.global_id == params['user_id']
    progress = Progress.schedule(Flusher, :flush_user_completely, user.global_id, user.user_name)
    render json: JsonApi::Progress.as_json(progress, :wrapper => true)
  end
  
  def hide_device
    user = User.find_by_path(params['user_id'])
    return unless allowed?(user, 'delete')
    device = Device.find_by_global_id(params['device_id'])
    if device && device.user_id == user.id
      device.settings['hidden'] = true
      device.save
      render json: JsonApi::Device.as_json(device, :current_device => @api_device)
    else
      api_error 400, {error: 'matching device not found'}
    end
  end
  
  def rename_device
    user = User.find_by_path(params['user_id'])
    return unless allowed?(user, 'edit')
    device = Device.find_by_global_id(params['device_id'])
    if device && device.user_id == user.id
      device.settings['name'] = params['device']['name']
      device.save
      render json: JsonApi::Device.as_json(device, :current_device => @api_device)
    else
      api_error 400, {error: 'matching device not found'}
    end
  end

  def history
    user_id = nil
    user = User.find_by_path(params['user_id'])
    return unless exists?(user, params['user_id'])
    if user
      return unless allowed?(user, 'admin_support_actions')
      user_id = user.global_id
    elsif @api_user.allows?(@api_user, 'admin_support_action')
      user_id = params['user_id']
    end
    return unless exists?(user_id)
    versions = User.user_versions(user_id)
    render json: JsonApi::UserVersion.paginate(params, versions, {:admin => Organization.admin_manager?(@api_user)})
  end
  
  def supervisors
    user = User.find_by_path(params['user_id'])
    return unless exists?(user, params['user_id'])
    return unless allowed?(user, 'supervise')
    supervisors = user.supervisors
    render json: JsonApi::User.paginate(params, supervisors, limited_identity: true, supervisee: user, prefix: "/users/#{user.global_id}/supervisors")
  end
  
  def supervisees
    user = User.find_by_path(params['user_id'])
    return unless exists?(user, params['user_id'])
    return unless allowed?(user, 'supervise')
    supervisees = user.supervisees
    render json: JsonApi::User.paginate(params, supervisees, limited_identity: true, supervisor: user, prefix: "/users/#{user.global_id}/supervisees")
  end
  
  def subscribe
    user = User.find_by_path(params['user_id'])
    return unless exists?(user, params['user_id'])

    admin = Organization.admin
    token = nil
    if params['token'] && params['token'].respond_to?(:to_unsafe_h)
      token = params['token'].to_unsafe_h
    elsif params['token'] && params['token'].respond_to?(:to_h)
      token = params['token'].to_h
    end
    if params['type'] == 'gift_code'
      return require_api_token unless @api_user
      return unless allowed?(user, 'edit')
      progress = Progress.schedule(user, :redeem_gift_token, token['code'])
    elsif['never_expires', 'eval', 'add_1', 'manual_supporter', 'add_voice', 'communicator_trial', 'force_logout'].include?(params['type'])
      return require_api_token unless @api_user
      return unless allowed?(user, 'admin_support_actions')
      progress = Progress.schedule(user, :subscription_override, params['type'], @api_user && @api_user.global_id)
    else
      if user.registration_code && params['confirmation'] == user.registration_code
      else
        return require_api_token unless @api_user
        return unless allowed?(user, 'edit')
      end
      progress = Progress.schedule(user, :process_subscription_token, token, params['type'])
    end
    render json: JsonApi::Progress.as_json(progress, :wrapper => true)
  end
  
  def unsubscribe
    user = User.find_by_path(params['user_id'])
    return unless allowed?(user, 'edit')
    progress = Progress.schedule(user, :process_subscription_token, 'token', 'unsubscribe')
    render json: JsonApi::Progress.as_json(progress, :wrapper => true)
  end
  
  def replace_board
    user = User.find_by_path(params['user_id'])
    old_board = Board.find_by_path(params['old_board_id'])
    new_board = Board.find_by_path(params['new_board_id'])
    return unless exists?(user, params['user_id']) && exists?(old_board, params['old_board_id']) && exists?(new_board, params['new_board_id'])
    return unless allowed?(user, 'edit') && allowed?(old_board, 'view') && allowed?(new_board, 'view')
    
    progress = Progress.schedule(user, :replace_board, params['old_board_id'], params['new_board_id'], params['ids_to_copy'], params['update_inline'], params['make_public'], user_for_paper_trail)
    render json: JsonApi::Progress.as_json(progress, :wrapper => true)
  end
  
  def copy_board_links
    user = User.find_by_path(params['user_id'])
    old_board = Board.find_by_path(params['old_board_id'])
    new_board = Board.find_by_path(params['new_board_id'])
    return unless exists?(user, params['user_id']) && exists?(old_board, params['old_board_id']) && exists?(new_board, params['new_board_id'])
    return unless allowed?(user, 'edit') && allowed?(old_board, 'view') && allowed?(new_board, 'view')
    
    progress = Progress.schedule(user, :copy_board_links, params['old_board_id'], params['new_board_id'], params['ids_to_copy'], params['make_public'], user_for_paper_trail)
    render json: JsonApi::Progress.as_json(progress, :wrapper => true)
  end
  
  def board_revisions
    user = User.find_by_path(params['user_id'])
    return unless exists?(user, params['user_id'])
    return unless allowed?(user, 'supervise')
    roots = []
    if user.settings['preferences']['home_board']
      roots << Board.find_by_global_id(user.settings['preferences']['home_board']['id'])
    end
    roots += Board.find_all_by_path(user.sidebar_boards.map{|b| b['key'] })
    all_ids = []
    roots.compact.each do |root|
      all_ids << root.global_id
      all_ids += root.settings['downstream_board_ids'] || []
    end
    all_ids.uniq!
    res = {}
    Board.select('id, current_revision, key').find_all_by_global_id(all_ids).each do |brd|
      res[brd.global_id] = brd.current_revision
      res[brd.key] = brd.current_revision
    end
    render json: res.to_json
  end
  
  def confirm_registration
    user = User.find_by_path(params['user_id'])
    if params['resend']
      sent = false
      if user.settings['pending'] != false
        sent = true
        UserMailer.schedule_delivery(:confirm_registration, user.global_id)
      end
      render json: {sent: sent}.to_json
    else
      confirmed = false
      if params['code'] && user && params['code'] == user.registration_code
        confirmed = true
        user.update_setting('pending', false)
      end
      render json: {:confirmed => confirmed}.to_json
    end
  end
  
  def forgot_password
    # TODO: throttling...
    user = User.find_by_path(params['key'])
    users = [user].compact
    if !user && params['key'] && params['key'].match(/@/)
      users = User.where(:email_hash => User.generate_email_hash(params['key']))
    end
    not_disabled_users = users.select{|u| !u.settings['email_disabled'] }
    reset_users = not_disabled_users.select{|u| u.generate_password_reset }
    if users.length > 0
      if reset_users.length > 0
        UserMailer.schedule_delivery(:forgot_password, reset_users.map(&:global_id))
        if reset_users.length == users.length
          render json: {email_sent: true, users: users.length}.to_json
        else
          message = "One or more of the users matching that name or email have had too many password resets, so those links weren't emailed to you. Please wait at least three hours and try again."
          render json: {email_sent: true, users: users.length, message: message}.to_json
        end
      else
        message = "All users matching that name or email have had too many password resets. Please wait at least three hours and try again."
        message = "The user matching that name or email has had too many password resets. Please wait at least three hours and try again." if users.length == 1
        message = "The email address for that account has been manually disabled." if not_disabled_users.length == 0
        api_error 400, {email_sent: false, users: 0, error: message, message: message}
      end
    else
      if params['key'] && params['key'].match(/@/)
        UserMailer.schedule_delivery(:login_no_user, params['key'])
        render json: {email_sent: true, users: 0}.to_json
      else
        message = "No users found with that name or email."
        api_error 400, {email_sent: false, users: 0, error: message, message: message}
      end
    end
  end
  
  def password_reset
    user = User.find_by_path(params['user_id'])
    # TODO: clear reset code after too many attempts, log data for troubleshooting
    if user && reset_token = user.reset_token_for_code(params['code'])
      render json: {valid: true, reset_token: reset_token}.to_json
    else
      api_error 400, {valid: false}
    end
  end
  
  def core_lists
    res = {defaults: WordData.core_lists}
    if params['user_id'] != 'none'
      user = User.find_by_path(params['user_id'])
      return unless exists?(user, params['user_id'])
      return unless allowed?(user, 'supervise')
      res[:for_user] = WordData.core_list_for(user)
      res[:reachable_for_user] = WordData.reachable_core_list_for(user)
    end
    render json: res
  end
  
  def update_core_list
    user = User.find_by_path(params['user_id'])
    return unless exists?(user, params['user_id'])
    return unless allowed?(user, 'edit')
    template = UserIntegration.find_by(:template => true, :integration_key => 'core_word_list')
    if !template
      return api_error 400, {error: 'no core word list integration defined'}
    end
    
    ui = UserIntegration.find_or_create_by(:template_integration => template, :user => user)
    ui.settings['core_word_list'] = {
      id: params['id'],
      words: params['words']
    }
    ui.save
    render json: {updated: true, words: ui.settings['core_word_list']}
  end
  
  def daily_stats
    user = User.find_by_path(params['user_id'])
    return unless allowed?(user, 'supervise')
    begin
      options = request.query_parameters
      render json: Stats.cached_daily_use(user.global_id, options)
    rescue Stats::StatsError => e
      api_error 400, {error: e.message}
    end
  end
  
  def daily_use
    user = User.find_by_path(params['user_id'])
    return unless exists?(user, params['user_id'])
    return unless allowed?(user, 'admin_support_actions')
    log = LogSession.find_by(:user_id => user.id, :log_type => 'daily_use')
    if log
      render json: JsonApi::Log.as_json(log, :wrapper => true, :permissions => @api_user).to_json
    else
      api_error 400, {error: 'no data available'}
    end
  end
  
  def hourly_stats
    user = User.find_by_path(params['user_id'])
    return unless allowed?(user, 'supervise')
    begin
      options = request.query_parameters
      render json: Stats.hourly_use(user.global_id, options)
    rescue Stats::StatsError => e
      api_error 400, {error: e.message}
    end
  end
  
  def protected_image
    user = User.find_by_path(params['user_id'])
    api_user = User.find_by_token(params['user_token'])
    valid_result = nil
    if !api_user
      expires_in 30.minutes, :public => true
      fallback = Uploader.fallback_image_url(params['image_id'], params['library'])
      if fallback
        res = grab_url(fallback)
        send_data res.body, :type => res.headers['Content-Type'], :disposition => 'inline'
        return
      end
      return redirect_to '/images/square.svg'
    else
      users = [user, api_user]
      users.each do |user|
        next if valid_result || !user
        safe_url = ButtonImage.cached_copy_url(request.original_url, user, false)
        if safe_url
          expires_in 12.days, :public => true
          return redirect_to safe_url
        end
        url = Uploader.found_image_url(params['image_id'], params['library'], user)
        if url
          url = url.sub(/^https/, 'http') if params['library'] == 'lessonpix'
          begin
            Timeout.timeout(5) do
              res = grab_url(url)
              if res.headers['Content-Type'] && res.headers['Content-Type'].match(/image/)
                valid_result = res
                expires_in 12.days, :public => true
              end
            end
          rescue Timeout::Error => e
            valid_result = nil
          end
        end
      end
    end
    if valid_result
      expires_in 24.hours, :public => true
      send_data valid_result.body, :type => valid_result.headers['Content-Type'], :disposition => 'inline'
    else
      expires_in 30.minutes, :public => true
      fallback = Uploader.fallback_image_url(params['image_id'], params['library'])
      if fallback
        res = grab_url(fallback)
        send_data res.body, :type => res.headers['Content-Type'], :disposition => 'inline'                
      else
        redirect_to '/images/error.png'
      end
    end
  end

  
  def translate
    user = User.find_by_path(params['user_id'])
    return unless exists?(user, params['user_id'])
    return unless allowed?(user, 'delete')
    res = WordData.translate_batch(params['words'].map{|w| {:text => w } }, params['source_lang'], params['destination_lang'])
    render json: res.to_json
  end
  
  protected
  def grab_url(url)
    url = url.sub(/^https/, 'http') if url.match(/lessonpix/)
    res = Typhoeus.get(url)
    if res.headers['Location']
      res = Typhoeus.get(URI.escape(res.headers['Location']))
    end
    res
  end
end
