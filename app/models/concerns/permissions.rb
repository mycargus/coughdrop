module Permissions
  extend ActiveSupport::Concern
  
  included do
    cattr_accessor :permissions_lookup
    cattr_accessor :cache_permissions
    self.permissions_lookup = []
  end
  
  def cache_key(prefix=nil)
    return nil unless self.id
    key = "#{self.class.to_s}#{self.id}-#{self.updated_at.to_f}"
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
  
  def allows?(user, action)
    if false && self.class.cache_permissions
      # check for an existing result keyed off the record's id and updated_at
      cache_key = (user && user.cache_key) || 'nobody'
      permissions = get_cached("permissions-for/#{cache_key}")
      # call permissions_for
      permissions ||= permissions_for(user)
      
      return permissions[action] == true
    end
    
    self.class.permissions_lookup.each do |actions, block|
      next unless actions.include?(action.to_s)
      next if block.arity == 1 && !user
      res = instance_exec(user, &block)
      return true if res == true
    end
    false
  end
  
  def permissions_for(user)
    all_permissions = []
    permissions_lookup.each{|actions, block| all_permissions += actions }
    all_permissions = all_permissions.uniq.sort
    granted_permissions = {
      'user_id' => (user && user.global_id)
    }.with_indifferent_access
    self.class.permissions_lookup.each do |actions, block|
      already_granted = granted_permissions.keys
      next if block.arity == 1 && !user
      next if actions - already_granted == []
      if instance_exec(user, &block)
        actions.each do |action|
          granted_permissions[action] = true
        end
      end
    end
    # cache the result with a 30-minute expiration keyed off the id and updated_at
    cache_key = (user && user.cache_key) || 'nobody'
    set_cached("permissions-for/#{cache_key}", granted_permissions)
    granted_permissions
  end
  
  module ClassMethods
    def cache_permissions
      self.cache_permissions = true
    end
    
    def add_permissions(*actions, &block)
      self.permissions_lookup << [actions.map(&:to_s), block]
    end
  end
end