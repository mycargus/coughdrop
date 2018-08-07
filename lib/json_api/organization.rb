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
      json['allotted_eval_licenses'] = org.settings['total_eval_licenses'] || 0
      json['used_licenses'] = 0
      json['used_evals'] = 0
      json['total_users'] = 0
      json['total_managers'] = 0
      json['total_supervisors'] = 0
      json['include_extras'] = org.settings['include_extras']
      user_ids = []
      UserLink.links_for(org).each do |link|
        if link['type'] == 'org_manager'
          json['total_managers'] += 1
        elsif link['type'] == 'org_supervisor'
          json['total_supervisors'] += 1
        elsif link['type'] == 'org_user'
          user_ids << link['user_id']
          json['total_users'] += 1
          json['used_evals'] += 1 if link['state']['eval']
          json['used_licenses'] += 1 if link['state']['sponsored']
        end
      end

      json['licenses_expire'] = org.settings['licenses_expire'] if org.settings['licenses_expire']
      json['created'] = org.created_at.iso8601
      json['children_orgs'] = org.children_orgs.map do |org|
        {
          'id' => org.global_id,
          'name' => org.settings['name']
        }
      end
      recent_sessions = LogSession.where(['started_at > ?', 2.weeks.ago])
      if !org.admin?
        recent_sessions = recent_sessions.where(:user_id => User.local_ids(user_ids))
      end
      json['recent_session_count'] = recent_sessions.count
      json['recent_session_user_count'] = recent_sessions.distinct.count('user_id')
    end
    if json['permissions'] && json['permissions']['edit']
      json['org_subscriptions'] = org.subscriptions.map{|u| JsonApi::User.as_json(u, limited_identity: true, subscription: true) }
    end
    if json['permissions'] && json['permissions']['view']
      json['default_home_board'] = org.settings['default_home_board']
      json['home_board_key'] = org.settings['default_home_board'] && org.settings['default_home_board']['key']
    end
    if json['permissions'] && json['permissions']['manage_subscription']
      json['purchase_history'] = org.purchase_history
    end
    
    json
  end
end
