class Api::OrganizationsController < ApplicationController
  before_filter :require_api_token
  before_filter :require_org, :except => [:show, :create, :index, :update, :destroy]

  def require_org
    @org = Organization.find_by_global_id(params['organization_id'])
    return false unless exists?(@org, params['organization_id'])
    true
  end
  
  def show
    org = Organization.find_by_global_id(params['id'])
    return unless exists?(org, params['id'])
    return unless allowed?(org, 'view')
    render json: JsonApi::Organization.as_json(org, :wrapper => true, :permissions => @api_user).to_json
  end
  
  def users
    return unless allowed?(@org, 'edit')
    users = @org.users
    if params['recent']
      users = users.order(id: :desc)
    else
      users = users.order('user_name')
    end
    prefix = "/organizations/#{@org.global_id}/users"
    render json: JsonApi::User.paginate(params, users, {:limited_identity => true, :organization => @org, :prefix => prefix})
  end
  
  def supervisors
    return unless allowed?(@org, 'edit')
    users = @org.supervisors.order('user_name')
    prefix = "/organizations/#{@org.global_id}/supervisors"
    render json: JsonApi::User.paginate(params, users, {:limited_identity => true, :organization => @org, :prefix => prefix})
  end

  def managers
    return unless allowed?(@org, 'edit')
    users = @org.managers.order('user_name')
    prefix = "/organizations/#{@org.global_id}/managers"
    render json: JsonApi::User.paginate(params, users, {:limited_identity => true, :organization => @org, :prefix => prefix})
  end
  
  def stats
    org = Organization.find_by_path(params['organization_id'])
    return unless allowed?(org, 'edit')
    sessions = LogSession.where(['started_at > ?', 4.months.ago])
    if !org.admin?
      # TODO: sharding
      sessions = sessions.where(:user_id => org.approved_users(false).map(&:id))
    end
    res = []
    sessions.group("date_trunc('week', started_at)").count.sort_by{|d, c| d }.each do |date, count|
      if date && date < Time.now
        res << {
          'timestamp' => date.to_time.to_i,
          'sessions' => count
        }
      end
    end
    render json: res.to_json
  end
  
  def admin_reports
    org = Organization.find_by_path(params['organization_id'])
    return unless allowed?(org, 'edit')
    if !['logged_2', 'unused_3', 'unused_6'].include?(params['report'])
      if !org.admin?
        return unless allowed?(org, 'impossible')
      end
    end
    if !params['report']
      return api_error 400, {:error => "report parameter required"}
    end
    users = nil
    stats = nil
    # TODO: make these actually efficient lookups
    if params['report'].match(/^unused_/)
      # logins not used in the last X months
      x = params['report'].split(/_/)[1].to_i
      users = User.where(['created_at < ?', x.months.ago])
      if !org.admin?
        # TODO: sharding
        users = user.where(:id => org.approved_users(false).map(&:id))
      end
      users = user.select{|u| u.devices.where(['updated_at < ?', x.months.ago]).count > 0 }
    elsif params['report'] == 'setup_but_expired'
      # logins that have set a home board, used it at least a week after registering, and have an expired trial
      x = 2
      users = User.where(['expires_at < ?', Time.now]).select{|u| u.settings['preferences'] && u.settings['preferences']['home_board'] && u.devices.where(['updated_at > ?', u.created_at + x.weeks]).count > 0 }
    elsif params['report'] == 'current_but_expired'
      # logins that have set a home board, used it in the last two weeks, and have an expired trial
      x = 2
      users = User.where(['expires_at < ?', Time.now]).select{|u| u.settings['preferences'] && u.settings['preferences']['home_board'] && u.devices.where(['updated_at > ?', x.weeks.ago]).count > 0 }
    elsif params['report'] == 'free_supervisor_without_supervisees'
      # logins that have changed to a free subscription after their trial but don't have any supervisees
      users = User.where({:expires_at => nil}).select{|u| u.settings['subscription'] && u.settings['subscription']['free_premium'] && u.supervised_user_ids.blank? }
    elsif params['report'].match(/recent_/)
      # logins signed up more than 3 weeks ago that have been used in the last week
      # TODO: this is too slow
      x = 3
      users = User.where(['created_at < ?', x.weeks.ago]).select{|u| u.devices.where(['updated_at > ?', 1.week.ago]).count > 0 }
    elsif params['report'] == 'new_users'
      x = 2
      users = User.where(['created_at > ?', x.weeks.ago])
    elsif params['report'].match(/logged_/)
      # logins that have generated logs in the last 2 weeks
      x = params['report'].split(/_/)[1].to_i
      sessions = LogSession.where(['created_at > ?', x.weeks.ago])
      if !org.admin?
        # TODO: sharding
        sessions = sessions.where(:user_id => org.approved_users(false).map(&:id))
      end
      user_ids = sessions.group('id, user_id').count('user_id').map(&:first)
      users = User.where(:id => user_ids)
    elsif params['report'] == 'missing_words'
      stats = RedisInit.default ? RedisInit.default.hgetall('missing_words') : {}
    elsif params['report'] == 'missing_symbols'
      stats = RedisInit.default ? RedisInit.default.hgetall('missing_symbols') : {}
    elsif params['report'] == 'overridden_parts_of_speech'
      stats = RedisInit.default ? RedisInit.default.hgetall('overridden_parts_of_speech') : {}
    elsif params['report'] == 'multiple_emails'
      counts = User.all.group('email_hash').having('count(*) > 1').count
      users = User.where({email_hash: counts.map(&:first)})
      emails = users.group_by(&:email_hash).sort_by{|e, us| us[0].settings['email'] }
      stats = {}
      emails.each do |email, users|
        u = users[0]
        stats[u.settings['email']] = users.map(&:user_name).join(',')
      end
    elsif params['report'] == 'premium_voices'
      voices = AuditEvent.where(['created_at > ? AND event_type = ?', 6.months.ago, 'voice_added'])
      stats = {}
      voices.each do |event|
        str = "#{event.created_at.strftime('%m-%Y')} #{event.data['voice_id']}"
        stats[str] ||= 0
        stats[str] += 1
      end
    elsif params['report'] == 'totals'
      stats = {}
      stats['users'] = User.count
      stats['boards'] = Board.count
      stats['devices'] = Device.count
      stats['logs'] = LogSession.count
      stats['organizations'] = Organization.count
    else
      return api_error 400, {:error => "unrecognized report: #{params['report']}"}
    end
    res = {}
    res[:user] = users.sort_by(&:user_name).map{|u| r = JsonApi::User.as_json(u, limited_identity: true); r['email'] = u.settings['email']; r } if users
    res[:stats] = stats if stats
    render json: res.to_json
  end
  
  def logs
    return unless allowed?(@org, 'manage')
    logs = @org.log_sessions.order(id: :desc)
    prefix = "/organizations/#{@org.global_id}/logs"
    render json: JsonApi::Log.paginate(params, logs, {:prefix => prefix})
  end
  
  def index
    admin_org = Organization.admin
    return unless allowed?(admin_org, 'edit')
    orgs = Organization.all.order(id: :desc)
    render json: JsonApi::Organization.paginate(params, orgs)
  end

  def create
    admin_org = Organization.admin
    return unless allowed?(admin_org, 'manage')
    org = Organization.process_new(params['organization'], {'updater' => @api_user})
    if org.errored?
      api_error(400, {error: "organization creation failed", errors: org && org.processing_errors})
    else
      render json: JsonApi::Organization.as_json(org, :wrapper => true, :permissions => @api_user).to_json
    end
  end

  def update
    org = Organization.find_by_global_id(params['id'])
    return unless exists?(org, params['id'])
    return unless allowed?(org, 'edit')
    if params['organization'] && !org.allows?(@api_user, 'update_licenses')
      params['organization'].delete('allotted_licenses') 
      params['organization'].delete('licenses_expire') 
    end
    if org.process(params['organization'], {'updater' => @api_user})
      render json: JsonApi::Organization.as_json(org, :wrapper => true, :permissions => @api_user).to_json
    else
      api_error(400, {error: "organization update failed", errors: org.processing_errors})
    end
  end
  
  def destroy
    org = Organization.find_by_global_id(params['id'])
    return unless exists?(org, params['id'])
    return unless allowed?(org, 'delete')
    org.destroy
    render json: JsonApi::Organization.as_json(org, :wrapper => true, :permissions => @api_user).to_json
  end
end
