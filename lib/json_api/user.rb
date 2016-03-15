module JsonApi::User
  extend JsonApi::Json
  
  TYPE_KEY = 'user'
  DEFAULT_PAGE = 25
  MAX_PAGE = 50
    
  def self.build_json(user, args={})
    json = {}
    
    json['id'] = user.global_id
    json['user_name'] = user.user_name

    # TODO: find a better home for this
    json['avatar_url'] = user.generated_avatar_url('fallback')
    json['fallback_avatar_url'] = json['avatar_url']
    json['link'] = "#{JsonApi::Json.current_host}/#{user.user_name}"
    
    
    if args.key?(:permissions)
      json['permissions'] = user.permissions_for(args[:permissions])
    end
    
    if json['permissions'] && json['permissions']['supervise']
      json['unread_messages'] = user.settings['unread_messages'] || 0
      json['preferences'] = {}
      ::User::PREFERENCE_PARAMS.each do |attr|
        json['preferences'][attr] = user.settings['preferences'][attr]
      end
      json['preferences']['progress'] = user.settings['preferences']['progress']
      json['feature_flags'] = FeatureFlags.frontend_flags_for(user)
      json['prior_avatar_urls'] = user.prior_avatar_urls
      
      json['preferences']['sidebar_boards'] = user.settings['preferences']['sidebar_boards'] || []
      json['preferences']['sidebar_boards'] = User.default_sidebar_boards if json['preferences']['sidebar_boards'].length == 0
      
      user.settings['preferences']['devices'] ||= {}
      nearest_device = nil
      if user.settings['preferences']['devices'].keys.length > 0
        devices = ::Device.where(:user_id => user.id).sort_by{|d| (d.settings['token_history'] || [])[-1] || 0 }.reverse
        last_access = devices.map(&:last_used_at).compact.max
        json['last_access'] = last_access && last_access.iso8601
        if args[:device]
          nearest_device = devices.detect{|d| d != args[:device] && d.settings['name'] == args[:device].settings['name'] && user.settings['preferences']['devices'][d.unique_device_key] }
        end
        nearest_device ||= devices.detect{|d| d.settings['token_history'] && d.settings['token_history'].length > 3 && user.settings['preferences']['devices'][d.unique_device_key] }
        if !nearest_device && user.settings['preferences']['devices'].keys.length == 2
          nearest_device ||= devices.detect{|d| user.settings['preferences']['devices'][d.unique_device_key] }
        end
        json['devices'] = devices.select{|d| !d.hidden? }.map{|d| JsonApi::Device.as_json(d, :current_device => args[:device]) }
      end
      nearest_device_key = (nearest_device && nearest_device.unique_device_key) || 'default'
      
      json['premium_voices'] = user.settings['premium_voices'] if user.settings['premium_voices']
      json['premium_voices'] ||= User.default_premium_voices
      json['preferences']['device'] = user.settings['preferences']['devices'][nearest_device_key] || {}
      if args[:device] && user.settings['preferences']['devices'][args[:device].unique_device_key]
        json['preferences']['device'].merge!(user.settings['preferences']['devices'][args[:device].unique_device_key])
        json['preferences']['device']['name'] = args[:device].settings['name'] || json['preferences']['device']['name']
      end

      json['prior_home_boards'] = (user.settings['all_home_boards'] || []).reverse
      if user.settings['preferences']['home_board']
        json['prior_home_boards'] = json['prior_home_boards'].select{|b| b['key'] != user.settings['preferences']['home_board']['key'] }
      end
      
      json['premium'] = user.premium?
      json['terms_agree'] = !!user.settings['terms_agreed']
      json['subscription'] = user.subscription_hash
      json['organizations'] = user.organization_hash
      json['is_managed'] = !!json['subscription']['is_managed'] # TODO: remove in later API revision, after like July 2016
      json['pending_board_shares'] = (user.settings['boards_shared_with_me'] || []).select{|s| s['pending'] }
      
      
      json['has_management_responsibility'] = Organization.manager?(user) # TODO: remove in later API revision, after like July 2016
      
      supervisors = user.supervisors
      supervisees = user.supervisees
      if supervisors.length > 0
        json['supervisors'] = supervisors[0, 10].map{|u| JsonApi::User.as_json(u, limited_identity: true, supervisee: user) }
      end
      if supervisees.length > 0
        json['supervisees'] = supervisees[0, 10].map{|u| JsonApi::User.as_json(u, limited_identity: true, supervisor: user) }
      end
      
      if user.settings['user_notifications'] && user.settings['user_notifications'].length > 0
        json['notifications'] = user.settings['user_notifications'].select{|n| Time.parse(n['added_at']) > 2.weeks.ago }[0, 5]
      end
    elsif json['permissions'] && json['permissions']['admin_support_actions']
      json['subscription'] = user.subscription_hash
      ::Device.where(:user_id => user.id).sort_by{|d| (d.settings['token_history'] || [])[-1] || 0 }.reverse
      json['devices'] = devices.select{|d| !d.hidden? }.map{|d| JsonApi::Device.as_json(d, :current_device => args[:device]) }
    end
    
    if args[:limited_identity]
      json['name'] = user.settings['name']
      json['avatar_url'] = user.generated_avatar_url
      json['unread_messages'] = user.settings['unread_messages'] || 0
      if args[:supervisor]
        json['edit_permission'] = args[:supervisor].edit_permission_for?(user)
        json['premium'] = user.premium?
      elsif args[:supervisee]
        json['edit_permission'] = user.edit_permission_for?(args[:supervisee])
      end
      if args[:subscription]
        json['subscription'] = user.subscription_hash
      end
      if args[:organization]
        if Organization.manager?(user)
          json['org_manager'] = args[:organization].manager?(user)
          json['org_assistant'] = args[:organization].assistant?(user)
        end
        if Organization.supervisor?(user)
          json['org_supervision_pending'] = args[:organization].pending_supervisor?(user)
          if !json['org_supervision_pending']
            supervisees = user.supervisees
            # TODO: sharding
            supervisees = args[:organization].users.where(:id => supervisees.map(&:id))
            if supervisees.length > 0
              json['org_supervisees'] = supervisees[0, 10].map{|u| JsonApi::User.as_json(u, limited_identity: true, supervisor: user) }
            end
          end
        end
        if Organization.managed?(user)
          json['org_pending'] = args[:organization].pending_user?(user)
          json['org_sponsored'] = args[:organization].sponsored_user?(user)
        end
      end
    elsif user.settings['public'] || (json['permissions'] && json['permissions']['view_detailed'])
      json['avatar_url'] = user.generated_avatar_url
      json['joined'] = user.created_at.iso8601
      json['email'] = user.settings['email'] 
      json.merge! user.settings.slice('name', 'public', 'description', 'details_url', 'location')
      json['pending'] = true if user.settings['pending']

      json['membership_type'] = user.premium? ? 'premium' : 'free'

      json['stats'] = {}
      json['stats']['starred_boards'] = user.settings['starred_boards'] || 0
      board_ids = user.board_set_ids
      # json['stats']['board_set'] = board_ids.uniq.length
      json['stats']['user_boards'] = Board.where(:user_id => user.id).count
      if json['permissions'] && json['permissions']['view_detailed']
        json['stats']['board_set_ids'] = board_ids.uniq
        if json['supervisees']
          json['stats']['board_set_ids_including_supervisees'] = user.board_set_ids(:include_supervisees => true)
        else 
          json['stats']['board_set_ids_including_supervisees'] = json['stats']['board_set_ids']
        end
      end
    end
    json
  end
end
