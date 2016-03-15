class Organization < ActiveRecord::Base
  include Permissions
  include Processable
  include GlobalId
  include SecureSerialize
  include Notifier
  secure_serialize :settings
  before_save :generate_defaults
  
  # cache should be invalidated if:
  # - a manager/assistant is added or removed
  add_permissions('view') { self.settings && self.settings['public'] == true }
  add_permissions('view', 'edit') {|user| self.assistant?(user) }
  add_permissions('view', 'edit', 'manage') {|user| self.manager?(user) }
  add_permissions('view', 'edit', 'manage', 'update_licenses', 'manage_subscription') {|user| Organization.admin && Organization.admin.manager?(user) }
  add_permissions('delete') {|user| Organization.admin && !self.admin && Organization.admin.manager?(user) }
  cache_permissions

  def generate_defaults
    self.settings ||= {}
    self.settings['name'] ||= "Unnamed Organization"
    true
  end
  
  def self.admin
    self.where(:admin => true).first
  end
  
  def log_sessions
    sessions = LogSession.where(:log_type => 'session')
    if !self.admin
      user_ids = self.users.map(&:id)
      sessions = sessions.where(:user_id => user_ids)
    end
    sessions.where(['started_at > ?', 6.months.ago]).order('started_at DESC')
  end
  
  def purchase_history
    ((self.settings || {})['purchase_events'] || []).reverse
  end
  
  def add_manager(user_key, full=false)
    user = User.find_by_path(user_key)
    raise "invalid user" unless user
    # raise "already associated with a different organization" if user.managed_organization_id && user.managed_organization_id != self.id
    user.settings ||= {}
    user.settings['manager_for'] ||= {}
    user.settings['manager_for'][self.global_id] = {'full_manager' => !!full, 'added' => Time.now.iso8601}
    self.attach_user(user, 'manager')
    user.managed_organization_id = self.id
    if full
      user.settings['full_manager'] = true
    end
    # TODO: trigger notification
    user.save
    self.touch
    true
  end
  
  def remove_manager(user_key)
    user = User.find_by_path(user_key)
    raise "invalid user" unless user
    # raise "associated with a different organization" if user.managed_organization_id && user.managed_organization_id != self.id
    user.managed_organization_id = nil
    user.settings ||= {}
    user.settings['manager_for'] ||= {}
    user.settings['manager_for'].delete(self.global_id)
    self.detach_user(user, 'manager')
    user.settings['full_manager'] = false
    # TODO: trigger notification
    user.save
    self.touch
    true
  end
  
  def add_supervisor(user_key, pending=true)
    user = User.find_by_path(user_key)
    raise "invalid user" unless user
    user.settings ||= {}
    user.settings['supervisor_for'] ||= {}
    user.settings['supervisor_for'][self.global_id] = {'pending' => pending, 'added' => Time.now.iso8601}
    self.attach_user(user, 'supervisor')
    user.save
    self.touch
    true
  end
  
  def approve_supervisor(user)
    if user.settings['supervisor_for'] && user.settings['supervisor_for'][self.global_id]
      self.add_supervisor(user.user_name, false)
      user.settings['supervisor_for'][self.global_id]['pending'] = false
    end
  end
  
  def reject_supervisor(user)
    if user.settings['supervisor_for'] && user.settings['supervisor_for'][self.global_id]
      self.remove_supervisor(user.user_name)
      user.settings['supervisor_for'].delete(self.global_id)
    end
  end
  
  def remove_supervisor(user_key)
    user = User.find_by_path(user_key)
    raise "invalid user" unless user
    user.settings ||= {}
    user.settings['supervisor_for'] ||= {}
    pending = user.settings['supervisor_for'][self.global_id] && user.settings['supervisor_for'][self.global_id]['pending']
    user.settings['supervisor_for'].delete(self.global_id)
    self.detach_user(user, 'supervisor')
    user.save
    self.touch
    notify('org_removed', {
      'user_id' => user.global_id,
      'user_type' => 'supervisor',
      'removed_at' => Time.now.iso8601
    }) unless pending
    true
  end

  def add_subscription(user_key)
    user = User.find_by_path(user_key)
    raise "invalid user" unless user
    self.attach_user(user, 'subscription')
    self.log_purchase_event({
      'type' => 'add_subscription',
      'user_name' => user.user_name,
      'user_id' => user.global_id
    })
    true
  end
  
  def remove_subscription(user_key)
    user = User.find_by_path(user_key)
    raise "invalid user" unless user
    self.detach_user(user, 'subscription')
    self.log_purchase_event({
      'type' => 'remove_subscription',
      'user_name' => user.user_name,
      'user_id' => user.global_id
    })
    true
  end
  
  def log_purchase_event(args, do_save=true)
    self.settings ||= {}
    self.settings['purchase_events'] ||= []
    args['logged_at'] = Time.now.iso8601
    self.settings['purchase_events'] << args
    self.save if do_save
  end
  
  def manager?(user)
    res = !!(user.managed_organization_id == self.id && user.settings && user.settings['full_manager'])
    res ||= user.settings && user.settings['manager_for'] && user.settings['manager_for'][self.global_id] && user.settings['manager_for'][self.global_id]['full_manager']
    !!res
  end
  
  def assistant?(user)
    res = !!(user.managed_organization_id == self.id)
    res ||= user.settings && user.settings['manager_for'] && user.settings['manager_for'][self.global_id]
    !!res
  end
  
  def supervisor?(user)
    res = user.settings && user.settings['supervisor_for'] && user.settings['supervisor_for'][self.global_id]
    !!res
  end
  
  def managed_user?(user)
    res = !!(user.managing_organization_id == self.id)
    res ||= user.settings && user.settings['managed_by'] && user.settings['managed_by'][self.global_id]
    !!res
  end
  
  def sponsored_user?(user)
    res = user.managing_organization_id == self.id && user.settings && user.settings['subscription'] && user.settings['subscription']['org_sponsored'] != false
    res ||= user.settings && user.settings['managed_by'] && user.settings['managed_by'][self.global_id] && user.settings['managed_by'][self.global_id]['sponsored']
    !!res
  end
  
  def pending_user?(user)
    res = managed_user?(user) && !!user.settings['subscription']['org_pending'] if user.settings && user.settings['subscription'] && user.settings['subscription']['org_pending'] != nil
    res ||= !!user.settings['managed_by'][self.global_id]['pending'] if user.settings && user.settings['managed_by'] && user.settings['managed_by'][self.global_id]
    !!res
  end
  
  def pending_supervisor?(user)
    res = user.settings['supervisor_for'][self.global_id]['pending'] if user.settings && user.settings['supervisor_for'] && user.settings['supervisor_for'][self.global_id]
    !!res
  end
  
  def self.sponsored?(user)
    res = user.managing_organization_id && user.settings && user.settings['subscription'] && user.settings['subscription']['org_sponsored']
    res ||= user.settings && user.settings['managed_by'] && user.settings['managed_by'].any?{|id, opts| opts['sponsored'] }
    !!res
  end
  
  def self.managed?(user)
    res = !!user.managing_organization_id
    res ||= !!(user.settings['managed_by'] && user.settings['managed_by'].keys.length > 0)
    res
  end
  
  def self.supervisor?(user)
    res = user.settings['supervisor_for'] && user.settings['supervisor_for'].keys.length > 0
    !!res
  end
  
  def self.manager?(user)
    res = !!user.managed_organization_id
    res ||= !!(user.settings['manager_for'] && user.settings['manager_for'].keys.length > 0)
    res
  end
  
  def self.manager_for?(manager, user)
    return false unless manager && user
    managed_orgs = []
    managed_orgs << user.related_global_id(user.managing_organization_id) if user.managing_organization_id && user.settings && user.settings['subscription'] && !user.settings['subscription']['org_pending']
    managed_orgs += user.settings['managed_by'].select{|id, opts| !opts['pending'] }.map{|id, opts| id } if user.settings && user.settings['managed_by']
    managed_orgs += user.settings['supervisor_for'].select{|id, opts| !opts['pending'] }.map{|id, opts| id } if user.settings && user.settings['supervisor_for']
    managing_orgs = []
    managing_orgs << manager.related_global_id(manager.managed_organization_id) if manager.managed_organization_id && manager.settings && manager.settings['full_manager']
    managing_orgs += manager.settings['manager_for'].select{|id, opts| opts['full_manager'] }.map{|id, opts| id } if manager.settings && manager.settings['manager_for']
    if (managed_orgs & managing_orgs).length > 0
      # if user and manager are part of the same org
      return true
    else
      return admin_manager?(manager)
    end
  end
  
  def self.admin_manager?(manager)
    managing_orgs = []
    managing_orgs << manager.related_global_id(manager.managed_organization_id) if manager.managed_organization_id && manager.settings && manager.settings['full_manager']
    managing_orgs += manager.settings['manager_for'].select{|id, opts| opts['full_manager'] }.map{|id, opts| id } if manager.settings && manager.settings['manager_for']
    
    if managing_orgs.length > 0
      # if manager is part of the global org (the order of lookups seems weird, but should be a little more efficient)
      org = self.admin
      return true if org && managing_orgs.include?(org.global_id)
    end
    false
  end
  
  def attach_user(user, user_type)
    self.settings['attached_user_ids'] ||= {}
    self.settings['attached_user_ids'][user_type] ||= []
    self.settings['attached_user_ids'][user_type] << user.global_id
    self.settings['attached_user_ids'][user_type].uniq!
    self.save
  end

  def detach_user(user, user_type)
    self.settings['attached_user_ids'] ||= {}
    self.settings['attached_user_ids'][user_type] ||= []
    self.settings['attached_user_ids'][user_type].select!{|id| id != user.global_id }
    self.save
  end
  
  def self.detach_user(user, user_type, except_org=nil)
    Organization.attached_orgs(user, true).each do |org|
      if org['type'] == user_type
        if !except_org || org['id'] != except_org.global_id
          org['org'].detach_user(user, user_type)
        end
      end
    end
  end
  
  def attached_users(user_type)
    user_ids = []
    if user_type == 'user'
      user_ids += User.where(:managing_organization_id => self.id).all.map(&:global_id)
    elsif user_type == 'manager'
      user_ids += User.where(:managed_organization_id => self.id).all.map(&:global_id)
    end
    user_ids += ((self.settings['attached_user_ids'] || {})[user_type] || []).uniq
    User.where(:id => User.local_ids(user_ids))
  end
  
  def users
    self.attached_users('user')
  end
  
  def sponsored_users
    # TODO: get rid of this double-lookup
    ids = self.attached_users('user').select{|u| self.sponsored_user?(u) }.map(&:id)
    User.where(:id => ids)
  end
  
  def managers
    self.attached_users('manager')
  end
  
  def supervisors
    self.attached_users('supervisor')
  end  
  
  def subscriptions
    self.attached_users('subscription')
  end
  
  def self.attached_orgs(user, include_org=false)
    res = []
    org_ids = []
    user.settings ||= {}
    (user.settings['managed_by'] || {}).each do |org_id, opts|
      org_ids << org_id
    end
    (user.settings['manager_for'] || {}).each do |org_id, opts|
      org_ids << org_id
    end
    (user.settings['supervisor_for'] || {}).each do |org_id, opts|
      org_ids << org_id
    end
    orgs = {}
    Organization.find_all_by_global_id(org_ids.uniq).each do |org|
      orgs[org.global_id] = org
    end
    (user.settings['managed_by'] || {}).each do |org_id, opts|
      org = orgs[org_id]
      e = {
        'id' => org_id,
        'name' => org.settings['name'],
        'type' => 'user',
        'added' => opts['added'],
        'pending' => opts['pending'],
        'sponsored' => opts['sponsored']
      }
      e['org'] = org if include_org
      res << e if org
    end
    (user.settings['manager_for'] || {}).each do |org_id, opts|
      org = orgs[org_id]
      e = {
        'id' => org_id,
        'name' => org.settings['name'],
        'type' => 'manager',
        'added' => opts['added'],
        'full_manager' => !!opts['full_manager']
      }
      e['org'] = org if include_org
      res << e if org
    end
    (user.settings['supervisor_for'] || {}).each do |org_id, opts|
      org = orgs[org_id]
      e = {
        'id' => org_id,
        'name' => org.settings['name'],
        'type' => 'supervisor',
        'added' => opts['added'],
        'pending' => !!opts['pending']
      }
      e['org'] = org if include_org
      res << e if org
    end
    res
  end
  
  def user?(user)
    managed_user?(user)
  end
  
  def add_user(user_key, pending, sponsored=true)
    user = User.find_by_path(user_key)
    raise "invalid user" unless user
    for_different_org = user.managing_organization_id && user.managing_organization_id != self.id
    for_different_org ||= user.settings && user.settings['managed_by'] && (user.settings['managed_by'].keys - [self.global_id]).length > 0
    raise "already associated with a different organization" if for_different_org
    user_count = User.where(['managing_organization_id = ? AND id != ?', self.id, user.id]).count
    raise "no licenses available" unless ((self.settings || {})['total_licenses'] || 0) > user_count
    user.update_subscription_organization(self.global_id, pending, sponsored)
    true
  end
  
  def remove_user(user_key)
    user = User.find_by_path(user_key)
    raise "invalid user" unless user
    for_different_org = user.managing_organization_id && user.managing_organization_id != self.id
    for_different_org ||= user.settings && user.settings['managed_by'] && (user.settings['managed_by'].keys - [self.global_id]).length > 0
    pending = user.settings['managed_by'] && user.settings['managed_by'][self.global_id] && user.settings['managed_by'][self.global_id]['pending']
    raise "already associated with a different organization" if for_different_org
    user.update_subscription_organization(nil)
    notify('org_removed', {
      'user_id' => user.global_id,
      'user_type' => 'user',
      'removed_at' => Time.now.iso8601
    }) unless pending
    true
  end

  def additional_listeners(type, args)
    if type == 'org_removed'
      u = User.find_by_global_id(args['user_id'])
      res = []
      res << u.record_code if u
      res
    end
  end
  
  def process_params(params, non_user_params)
    self.settings ||= {}
    self.settings['name'] = params['name'] if params['name']
    raise "updated required" unless non_user_params['updater']
    if params[:allotted_licenses]
      total = params[:allotted_licenses].to_i
      used = User.where(:managing_organization_id => self.id).count
      if total < used
        add_processing_error("too few licenses, remove some users first")
        return false
      end
      self.settings['total_licenses'] = total
      self.log_purchase_event({
        'type' => 'update_license_count',
        'count' => total,
        'updater_id' => non_user_params['updater'].global_id,
        'updater_user_name' => non_user_params['updater'].user_name
      }, false)
    end
    if params[:management_action]
      if !self.id
        add_processing_error("can't manage users on create") 
        return false
      end

      action, key = params[:management_action].split(/-/, 2)
      begin
        if action == 'add_user'
          self.add_user(key, true)
        elsif action == 'add_unsponsored_user'
          self.add_user(key, true, false)
        elsif action == 'add_supervisor'
          self.add_supervisor(key, true)
        elsif action == 'add_assistant' || action == 'add_manager'
          self.add_manager(key, action == 'add_manager')
        elsif action == 'remove_user'
          self.remove_user(key)
        elsif action == 'remove_supervisor'
          self.remove_supervisor(key)
        elsif action == 'remove_assistant' || action == 'remove_manager'
          self.remove_manager(key)
        end
      rescue => e
        add_processing_error("user management action failed: #{e.message}")
        return false
      end
    end
    true
  end
end
