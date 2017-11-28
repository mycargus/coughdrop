module JsonApi::Unit
  extend JsonApi::Json
  
  TYPE_KEY = 'unit'
  DEFAULT_PAGE = 10
  MAX_PAGE = 25
    
  def self.build_json(unit, args={})
    json = {}
    
    json['id'] = unit.global_id
    json['name'] = unit.settings['name'] || "Unnamed Room"
    
    users_hash = args[:page_data] && args[:page_data][:users_hash]
    if !users_hash
      users = ::User.find_all_by_global_id(unit.all_user_ids)
      users_hash = {}
      users.each{|u| users_hash[u.global_id] = u }
    end
    
    links = UserLink.links_for(unit)
    json['supervisors'] = []
    json['communicators'] = []
    UserLink.links_for(unit).each do |link|
      user = users_hash[link['user_id']]
      if user
        if link['type'] == 'org_unit_supervisor'
          hash = JsonApi::User.as_json(user, limited_identity: true)
          hash['org_unit_edit_permission'] = !!(link['state'] && link['state']['edit_permission'])
          json['supervisors'] << hash
        elsif link['type'] == 'org_unit_communicator'
          json['communicators'] << JsonApi::User.as_json(user, limited_identity: true)
        end
      end
    end

    if args.key?(:permissions)
      json['permissions'] = unit.permissions_for(args[:permissions])
    end
    
    json
  end
  
  def self.page_data(results)
    res = {}
    ids = results.map(&:all_user_ids).flatten.uniq
    users = User.find_all_by_global_id(ids)
    res[:users_hash] = {}
    users.each{|u| res[:users_hash][u.global_id] = u }
    res
  end
end
