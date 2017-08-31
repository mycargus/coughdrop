module Permissions
  extend ActiveSupport::Concern
  
  ALL_SCOPES = [
    'read_logs', 'full', 'read_boards', 'read_profile'
  ]
  
  included do
    cattr_accessor :permissions_lookup
    cattr_accessor :allow_cached_permissions
    cattr_accessor :default_permission_scopes
    self.permissions_lookup = []
    self.default_permission_scopes = ['full']
  end
  
  def cache_key(prefix=nil)
    id = self.id || 'nil'
    updated = (self.updated_at || Time.now).to_f
    key = "#{self.class.to_s}#{id}-#{updated}:#{RedisInit.cache_token}"
    if prefix
      key = prefix + "/" + key
    end
    key
  end
  
  def set_cached(prefix, data, expires=nil)
    expires ||= 30.minutes.to_i
    RedisInit.permissions.setex(self.cache_key(prefix), expires, data.to_json)
  end
  
  def get_cached(prefix)
    cache_string = RedisInit.permissions.get(self.cache_key(prefix))
    cache = nil
    if cache_string
      cache = JSON.parse(cache_string) rescue nil
    end
    cache
  end
  
  def clear_cached(prefix)
    RedisInit.permissions.del(self.cache_key(prefix))
  end
  
  def allows?(user, action, relevant_scopes=nil)
    relevant_scopes ||= self.class.default_permission_scopes
    relevant_scopes += ['*']
    if self.class.allow_cached_permissions
      # check for an existing result keyed off the record's id and updated_at
      permissions = permissions_for(user, relevant_scopes)
      action.instance_variable_set('@scope_rejected', permissions[action] == false)
      
      return permissions[action] == true
    end

    scope_rejected = false    
    self.class.permissions_lookup.each do |actions, block, allowed_scopes|
      next unless actions.include?(action.to_s)
      next if block.arity == 1 && !user
      res = instance_exec(user, &block)
      if res == true
        if (allowed_scopes & relevant_scopes).length > 0
          return true
        else
          scope_rejected = true
        end
      end
    end
    action.instance_variable_set('@scope_rejected', !!scope_rejected)
    return false
  end
  
  def permissions_for(user, relevant_scopes=nil)
    relevant_scopes ||= user && user.permission_scopes_device && user.permission_scopes_device.permission_scopes
    relevant_scopes ||= self.class.default_permission_scopes
    relevant_scopes += ['*']
    if self.class.allow_cached_permissions
      cache_key = (user && user.cache_key) || "nobody"
      cache_key += "/scopes_#{relevant_scopes.join(',')}"
      permissions = get_cached("permissions-for/#{cache_key}")
      return permissions if permissions
    end

    granted_permissions = {
      'user_id' => (user && user.global_id)
    }.with_indifferent_access
    self.class.permissions_lookup.each do |actions, block, allowed_scopes|
      already_granted = granted_permissions.keys
      next if block.arity == 1 && !user
      next if actions - already_granted == []
      if instance_exec(user, &block)
        actions.each do |action|
          if (allowed_scopes & relevant_scopes).length > 0
            granted_permissions[action] = true
          else
            granted_permissions[action] ||= false
          end
        end
      end
    end
    # cache the result with a 30-minute expiration keyed off the id and updated_at
    set_cached("permissions-for/#{cache_key}", granted_permissions) if self.class.allow_cached_permissions
    granted_permissions
  end
  
  module ClassMethods
    def cache_permissions
      self.allow_cached_permissions = true
    end
    
    def add_permissions(*actions, &block)
      scopes = ['full']
      if actions[-1].is_a?(Array)
        scopes += actions.pop
      end
      self.permissions_lookup << [actions.map(&:to_s), block, scopes.sort.uniq]
    end
  end
end