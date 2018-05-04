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
      json['sync_stamp'] = user.updated_at.utc.iso8601
      json['unread_messages'] = user.settings['unread_messages'] || 0
      json['user_token'] = user.user_token
      json['global_integrations'] = UserIntegration.global_integrations
      json['preferences'] = {}
      ::User::PREFERENCE_PARAMS.each do |attr|
        json['preferences'][attr] = user.settings['preferences'][attr]
      end
      json['target_words'] = user.settings['target_words'].slice('generated', 'list') if user.settings['target_words']
      json['preferences']['home_board'] = user.settings['preferences']['home_board']
      json['preferences']['progress'] = user.settings['preferences']['progress']
      json['preferences']['protected_usage'] = !user.external_email_allowed?
      if json['preferences']['cookies'] == nil
        json['preferences']['cookies'] = true
      end
      if FeatureFlags.user_created_after?(user, 'word_suggestion_images')
        json['preferences']['word_suggestion_images'] = true if user.settings['preferences']['word_suggestion_images'] == nil
      end
      if json['preferences']['symbol_background'] == nil
        json['preferences']['symbol_background'] = FeatureFlags.user_created_after?(user, 'symbol_background') ? 'clear' : 'white'
      end
      json['feature_flags'] = FeatureFlags.frontend_flags_for(user)
      json['prior_avatar_urls'] = user.prior_avatar_urls
      
      json['goal'] = user.settings['primary_goal']
      json['cell_phone'] = user.settings['cell_phone']
      
      json['preferences']['sidebar_boards'] = user.sidebar_boards
      
      user.settings['preferences']['devices'] ||= {}
      nearest_device = nil
      if user.settings['preferences']['devices'].keys.length > 0
        devices = ::Device.where(:user_id => user.id, :user_integration_id => nil).sort_by{|d| (d.settings['token_history'] || [])[-1] || 0 }.reverse
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
      json['premium_voices'] ||= user.default_premium_voices
      json['preferences']['device'] = {}.merge(user.settings['preferences']['devices'][nearest_device_key] || {})
      json['preferences']['device'].delete('ever_synced')
      if args[:device] && user.settings['preferences']['devices'][args[:device].unique_device_key]
        json['preferences']['device'] = json['preferences']['device'].merge(user.settings['preferences']['devices'][args[:device].unique_device_key])
        json['preferences']['device']['name'] = args[:device].settings['name'] || json['preferences']['device']['name']
      end
      if !args[:device] || FeatureFlags.user_created_after?(args[:device], 'browser_no_autosync')
        json['preferences']['device']['ever_synced'] ||= false
      else
        json['preferences']['device']['ever_synced'] = true if json['preferences']['device']['ever_synced'] == nil
      end
      if FeatureFlags.user_created_after?(user, 'folder_icons')
        json['preferences']['folder_icons'] ||= false
      else
        json['preferences']['folder_icons'] = true if json['preferences']['folder_icons'] == nil
      end
      json['preferences']['device']['voice'] ||= {}
      json['preferences']['device']['alternate_voice'] ||= {}

      json['prior_home_boards'] = (user.settings['all_home_boards'] || []).reverse
      if user.settings['preferences']['home_board']
        json['prior_home_boards'] = json['prior_home_boards'].select{|b| b['key'] != user.settings['preferences']['home_board']['key'] }
      end
      
      json['premium'] = user.premium?
      json['terms_agree'] = !!user.settings['terms_agreed']
      json['subscription'] = user.subscription_hash
      json['organizations'] = user.organization_hash
      json['purchase_duration'] = (user.purchase_credit_duration / 1.year.to_f).round(1)
      json['pending_board_shares'] = UserLink.links_for(user).select{|l| l['user_id'] == user.global_id && l['state'] && l['state']['pending'] }.map{|link|
        {
          'user_name' => link['state']['sharer_user_name'] || (link['state']['board_key'] || '').split(/\//)[0],
          'board_key' => link['state']['board_key'],
          'board_id' => link['record_code'].split(/:/)[1],
          'include_downstream' => !!link['state']['include_downstream'],
          'allow_editing' => !!link['state']['allow_editing'],
          'pending' => !!link['state']['pending'],
          'user_id' => link['user_id']
        }
      }
      
      supervisors = user.supervisors
      supervisees = user.supervisees
      if supervisors.length > 0
        json['supervisors'] = supervisors[0, 10].map{|u| JsonApi::User.as_json(u, limited_identity: true, supervisee: user) }
      end
      if supervisees.length > 0
        json['supervisees'] = supervisees[0, 10].map{|u| JsonApi::User.as_json(u, limited_identity: true, supervisor: user) }
        json['supervised_units'] = OrganizationUnit.supervised_units(user).map{|ou|
          {
            'id' => ou.global_id,
            'organization_id' => ou.related_global_id(ou.organization_id),
            'name' => ou.settings['name']
          }
        }
      end
      if json['subscription'] && json['subscription']['free_premium']
        json['subscription']['limited_supervisor'] = true
        json['subscription']['limited_supervisor'] = false if Organization.supervisor?(user)
        # in case you get stuck on the comparator again, this is saying for anybody who signed up
        # less than 2 months ago
        json['subscription']['limited_supervisor'] = false if user.created_at > 2.months.ago 
        json['subscription']['limited_supervisor'] = false if supervisees.any?{|u| u.premium? }
      end
      
      if user.settings['user_notifications'] && user.settings['user_notifications'].length > 0
        cutoff = 6.weeks.ago.iso8601
        unread_cutoff = user.settings['user_notifications_cutoff'] || user.created_at.utc.iso8601
        json['notifications'] = user.settings['user_notifications'].select{|n| n['added_at'] > cutoff }
        json['notifications'].each{|n| n['unread'] = true if n['added_at'] > unread_cutoff }
      end
      json['read_notifications'] = false
    elsif json['permissions'] && json['permissions']['admin_support_actions']
      json['subscription'] = user.subscription_hash
      ::Device.where(:user_id => user.id).sort_by{|d| (d.settings['token_history'] || [])[-1] || 0 }.reverse
      json['devices'] = devices.select{|d| !d.hidden? }.map{|d| JsonApi::Device.as_json(d, :current_device => args[:device]) }
    elsif args[:include_subscription]
      json['subscription'] = user.subscription_hash
    end
    
    if args[:limited_identity]
      json['name'] = user.settings['name']
      json['avatar_url'] = user.generated_avatar_url
      json['unread_messages'] = user.settings['unread_messages'] || 0
      json['email'] = user.settings['email'] if args[:include_email]
      if args[:supervisor]
        json['edit_permission'] = args[:supervisor].edit_permission_for?(user)
        json['premium'] = user.premium?
        json['goal'] = user.settings['primary_goal']
        json['target_words'] = user.settings['target_words'].slice('generated', 'list') if user.settings['target_words']
        json['home_board_key'] = user.settings['preferences'] && user.settings['preferences']['home_board'] && user.settings['preferences']['home_board']['key']
      elsif args[:supervisee]
        json['edit_permission'] = user.edit_permission_for?(args[:supervisee])
        org_unit = (user.org_units_for_supervising(args[:supervisee]) || [])[0]
        if org_unit
          # json['organization_unit_name'] = org_unit.settings['name']
          json['organization_unit_id'] = org_unit.global_id
        end
      end
      if args[:subscription]
        json['subscription'] = user.subscription_hash
      end
      if args[:organization]
        if args[:organization_manager]
          json['goal'] = user.settings['primary_goal']
        end
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
          json['org_eval'] = args[:organization].eval_user?(user)
          json['joined'] = user.created_at.iso8601
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
