module JsonApi::Organization
  extend JsonApi::Json
  
  TYPE_KEY = 'organization'
  DEFAULT_PAGE = 15
  MAX_PAGE = 25
  
  def self.build_json(org, args={})
    json = {}
    json['id'] = org.global_id
    json['name'] = org.settings['name']
    json['admin'] = !!org.admin
    
    if args.key?(:permissions)
      json['permissions'] = org.permissions_for(args[:permissions])
    end
    
    if json['permissions'] && json['permissions']['edit']
      json['allotted_licenses'] = org.settings['total_licenses'] || 0
      org.sponsored_users(false)
      json['used_licenses'] = org.sponsored_users(false).count
      json['total_users'] = org.users.count
      json['total_managers'] = org.managers.count
      json['licenses_expire'] = org.settings['licenses_expire'] if org.settings['licenses_expire']
      json['total_supervisors'] = org.supervisors.count
      json['created'] = org.created_at.iso8601
      json['children_orgs'] = org.children_orgs.map do |org|
        {
          'id' => org.global_id,
          'name' => org.settings['name']
        }
      end
      recent_sessions = LogSession.where(['started_at > ?', 2.weeks.ago])
      if !org.admin?
        recent_sessions = recent_sessions.where(:user_id => org.users.map(&:id))
      end
      json['recent_session_count'] = recent_sessions.count
      json['recent_session_user_count'] = recent_sessions.distinct.count('user_id')
    end
    if json['permissions'] && json['permissions']['edit']
      json['org_subscriptions'] = org.subscriptions.map{|u| JsonApi::User.as_json(u, limited_identity: true, subscription: true) }
    end
    if json['permissions'] && json['permissions']['manage_subscription']
      json['purchase_history'] = org.purchase_history
    end
    
    json
  end
end
