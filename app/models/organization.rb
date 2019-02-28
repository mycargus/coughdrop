class Organization < ActiveRecord::Base
  include Permissions
  include Processable
  include GlobalId
  include Async
  include SecureSerialize
  include Notifier
  secure_serialize :settings
  before_save :generate_defaults
  after_save :touch_parent
  replicated_model  
  
  # cache should be invalidated if:
  # - a manager/assistant is added or removed
  add_permissions('view') { self.settings && self.settings['public'] == true }
  add_permissions('view', 'edit') {|user| self.assistant?(user) }
  add_permissions('view', 'edit', 'manage') {|user| self.manager?(user) }
  add_permissions('view', 'edit', 'manage') {|user| self.upstream_manager?(user) }
  add_permissions('view', 'edit', 'manage', 'update_licenses', 'manage_subscription') {|user| Organization.admin && Organization.admin.manager?(user) }
  add_permissions('view') {|user| self.supervisor?(user) }
  add_permissions('delete') {|user| Organization.admin && !self.admin && Organization.admin.manager?(user) }
  cache_permissions

  def generate_defaults
    self.settings ||= {}
    self.settings['name'] ||= "Unnamed Organization"
    self.schedule(:org_assertions, 'all', nil) if self.settings['include_extras'] && @processed
    @processed = false
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
    raise "invalid user, #{user_key}" unless user
#     user.settings ||= {}
#     user.settings['manager_for'] ||= {}
#     user.settings['manager_for'][self.global_id] = {'full_manager' => !!full, 'added' => Time.now.iso8601}
    user.settings['preferences']['role'] = 'supporter'
    user.assert_current_record!
    user.save
#     self.attach_user(user, 'manager')
    # TODO: trigger notification
    if user.grace_period? && !Organization.managed?(user)
      user.update_subscription({
        'subscribe' => true,
        'subscription_id' => 'free_auto_adjusted',
        'token_summary' => "Automatically-set Supporter Account",
        'plan_id' => 'slp_monthly_free'
      })
    end
    link = UserLink.generate(user, self, 'org_manager')
    link.data['state']['added'] ||= Time.now.iso8601
    link.data['state']['full_manager'] = true if full
    link.save!
    self.schedule(:org_assertions, user.global_id, 'manager')
    self.touch
    true
  rescue ActiveRecord::StaleObjectError
    self.schedule(:add_manager, user_key, full)
  end

  def org_assertions(user_id, user_type)
    if user_type == 'user' || user_type == 'supervisor' || user_id == 'all'
      if self.settings['include_extras']
        users = []
        if user_id == 'all'
          users += self.supervisors.select{|u| !self.pending_supervisor?(u) }
          users += self.sponsored_users.select{|u| !self.pending_user?(u) }
          users += self.eval_users.select{|u| !self.pending_user?(u) }
        else
          user = User.find_by_global_id(user_id)
          if user
            if user_type == 'user' && self.sponsored_users.include?(user) && !self.pending_user?(user)
              users = [user]
            elsif user_type == 'supervisor' && self.supervisors.include?(user) && !self.pending_supervisor?(user)
              users = [user]
            end
          end
        end
        users.each do |user|
          self.settings['extras_activations'] ||= []
          if !user.reload.subscription_hash['extras_enabled']
            User.purchase_extras({'user_id' => user.global_id, 'source' => 'org_added'})
            self.settings['extras_activations'] << {user_id: user.global_id, activated_at: Time.now.iso8601}
          end
          self.save
        end
      end
    end
  end
  
  def remove_manager(user_key)
    user = User.find_by_path(user_key)
    raise "invalid user, #{user_key}" unless user
#     user.settings ||= {}
#     user.settings['manager_for'] ||= {}
#     user.settings['manager_for'].delete(self.global_id)
    self.detach_user(user, 'manager')
    # TODO: trigger notification
#     user.assert_current_record!
#     user.save
    self.touch
    true
  rescue ActiveRecord::StaleObjectError
    self.schedule(:remove_manager, user_key)
  end
  
  def add_supervisor(user_key, pending=true)
    user = User.find_by_path(user_key)
    raise "invalid user, #{user_key}" unless user
    if user.settings['authored_organization_id'] && user.settings['authored_organization_id'] == self.global_id && user.created_at > 2.weeks.ago
      pending = false
    end
#     user.settings ||= {}
#     user.settings['supervisor_for'] ||= {}
#     user.settings['supervisor_for'][self.global_id] = {'pending' => pending, 'added' => Time.now.iso8601}
    user.settings['preferences']['role'] = 'supporter'
    user.assert_current_record!
    user.save
#     self.attach_user(user, 'supervisor')
    if user.grace_period? && !Organization.managed?(user)
      user.update_subscription({
        'subscribe' => true,
        'subscription_id' => 'free_auto_adjusted',
        'token_summary' => "Automatically-set Supporter Account",
        'plan_id' => 'slp_monthly_free'
      })
    end
    link = UserLink.generate(user, self, 'org_supervisor')
    link.data['state']['pending'] = pending unless link.data['state']['pending'] == false
    link.data['state']['added'] ||= Time.now.iso8601
    link.save
    self.schedule(:org_assertions, user.global_id, 'supervisor')
    self.touch
    true
  rescue ActiveRecord::StaleObjectError
    self.schedule(:add_supervisor, user_key, pending)
  end
  
  def approve_supervisor(user)
    links = UserLink.links_for(user).select{|l| l['type'] == 'org_supervisor' && l['record_code'] == Webhook.get_record_code(self) }
    if links.length > 0
      link = UserLink.generate(user, self, 'org_supervisor')
      link.data['state']['pending'] = false
      link.save
      self.schedule(:org_assertions, user.global_id, 'supervisor')
    end
#     if user.settings['supervisor_for'] && user.settings['supervisor_for'][self.global_id]
#       self.add_supervisor(user.user_name, false)
#       user.settings['supervisor_for'][self.global_id]['pending'] = false
#     end
  end
  
  def reject_supervisor(user)
    UserLink.remove(user, self, 'org_supervisor')
    self.schedule(:org_assertions, user.global_id, 'supervisor')
#     if user.settings['supervisor_for'] && user.settings['supervisor_for'][self.global_id]
#       self.remove_supervisor(user.user_name)
#       user.settings['supervisor_for'].delete(self.global_id)
#     end
  end
  
  def remove_supervisor(user_key)
    user = User.find_by_path(user_key)
    raise "invalid user, #{user_key}" unless user
    pending = !!UserLink.links_for(user).detect{|l| l['type'] == 'org_supervisor' && l['record_code'] == Webhook.get_record_code(self) && l['state']['pending'] }
#     user.settings ||= {}
#     user.settings['supervisor_for'] ||= {}
#     pending = user.settings['supervisor_for'][self.global_id] && user.settings['supervisor_for'][self.global_id]['pending']
#     user.settings['supervisor_for'].delete(self.global_id)
#     user.assert_current_record!
#     user.save
    self.detach_user(user, 'supervisor')
#     self.touch
    notify('org_removed', {
      'user_id' => user.global_id,
      'user_type' => 'supervisor',
      'removed_at' => Time.now.iso8601
    }) unless pending
    OrganizationUnit.schedule(:remove_as_member, user_key, 'supervisor', self.global_id)
    true
  rescue ActiveRecord::StaleObjectError
    self.schedule(:remove_supervisor, user_key)
  end

  def add_subscription(user_key)
    user = User.find_by_path(user_key)
    raise "invalid user, #{user_key}" unless user
    link = UserLink.generate(user, self, 'org_subscription')
    link.save
#     self.attach_user(user, 'subscription')
    self.log_purchase_event({
      'type' => 'add_subscription',
      'user_name' => user.user_name,
      'user_id' => user.global_id
    })
    true
  end
  
  def remove_subscription(user_key)
    user = User.find_by_path(user_key)
    raise "invalid user, #{user_key}" unless user
    UserLink.remove(user, self, 'org_subscription')
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
    links = UserLink.links_for(user)
    !!links.detect{|l| l['type'] == 'org_manager' && l['record_code'] == Webhook.get_record_code(self) && l['user_id'] == user.global_id && l['state']['full_manager'] }
  end
  
  def upstream_manager?(user)
    org_record_codes = self.upstream_orgs.map{|o| Webhook.get_record_code(o) }
    links = UserLink.links_for(user)
    !!links.detect{|l| l['type'] == 'org_manager' && org_record_codes.include?(l['record_code']) && l['user_id'] == user.global_id && l['state']['full_manager'] }
  end
  
  def assistant?(user)
    links = UserLink.links_for(user)
    !!links.detect{|l| l['type'] == 'org_manager' && l['record_code'] == Webhook.get_record_code(self) && l['user_id'] == user.global_id }
  end
  
  def supervisor?(user)
    links = UserLink.links_for(user)
    !!links.detect{|l| l['type'] == 'org_supervisor' && l['record_code'] == Webhook.get_record_code(self) && l['user_id'] == user.global_id }
  end
  
  def managed_user?(user)
    links = UserLink.links_for(user)
    res = !!links.detect{|l| l['type'] == 'org_user' && l['record_code'] == Webhook.get_record_code(self) && l['user_id'] == user.global_id }
    res
  end
  
  def sponsored_user?(user)
    links = UserLink.links_for(user)
    !!links.detect{|l| l['type'] == 'org_user' && l['record_code'] == Webhook.get_record_code(self) && l['user_id'] == user.global_id && l['state']['sponsored'] }
  end
  
  def eval_user?(user)
    links = UserLink.links_for(user)
    !!links.detect{|l| l['type'] == 'org_user' && l['record_code'] == Webhook.get_record_code(self) && l['user_id'] == user.global_id && l['state']['eval'] }
  end
  
  def pending_user?(user)
    links = UserLink.links_for(user)
    !!links.detect{|l| l['type'] == 'org_user' && l['record_code'] == Webhook.get_record_code(self) && l['user_id'] == user.global_id && l['state']['pending'] }
  end
  
  def pending_supervisor?(user)
    links = UserLink.links_for(user)
    !!links.detect{|l| l['type'] == 'org_supervisor' && l['record_code'] == Webhook.get_record_code(self) && l['user_id'] == user.global_id && l['state']['pending'] }
  end
  
  def self.sponsored?(user)
    links = UserLink.links_for(user)
    !!links.detect{|l| l['type'] == 'org_user' && l['user_id'] == user.global_id && l['state']['sponsored'] }
  end
  
  def self.managed?(user)
    links = UserLink.links_for(user)
    !!links.detect{|l| l['type'] == 'org_user' }
  end
  
  def self.supervisor?(user)
    links = UserLink.links_for(user)
    !!links.detect{|l| l['type'] == 'org_supervisor' }
  end
  
  def self.manager?(user)
    links = UserLink.links_for(user)
    !!links.detect{|l| l['type'] == 'org_manager' }
  end
  
#   def self.upgrade_management_settings
#     User.where('managed_organization_id IS NOT NULL').each do |user|
#       org = user.managed_organization
#       user.settings['manager_for'] ||= {}
#       if org && !user.settings['manager_for'][org.global_id]
#         user.settings['manager_for'][org.global_id] = {
#           'full_manager' => !!user.settings['full_manager']
#         }
#       end
#       user.settings.delete('full_manager')
#       user.managed_organization_id = nil
#       user.save
#     end
#     User.where('managing_organization_id IS NOT NULL').each do |user|
#       org = user.managing_organization
#       user.settings['managed_by'] ||= {}
#       if org && !user.settings['managed_by'][org.global_id]
#         user.settings['managed_by'][org.global_id] = {
#           'pending' => !!(user.settings['subscription'] && user.settings['subscription']['org_pending']),
#           'sponsored' => true
#         }
#       end
#       user.settings['subscription'].delete('org_pending') if user.settings['subscription']
#       user.managing_organization_id = nil
#       user.save
#     end
#     Organization.all.each do |org|
#       org.sponsored_users.each do |user|
#         org.attach_user(user, 'sponsored_user')
#       end
#       org.approved_users.each do |user|
#         org.attach_user(user, 'approved_user')
#       end
#     end
#   end
  
  def self.manager_for?(manager, user, include_admin_managers=true)
    return false unless manager && user
    manager_orgs = UserLink.links_for(manager).select{|l| l['type'] == 'org_manager' && l['user_id'] == manager.global_id && l['state']['full_manager'] }.map{|l| l['record_code'] }
    user_orgs = UserLink.links_for(user).select{|l| (l['type'] == 'org_user' || l['type'] == 'org_supervisor') && l['user_id'] == user.global_id && !l['state']['pending'] }.map{|l| l['record_code'] }
    if (manager_orgs & user_orgs).length > 0
      # if user and manager are part of the same org
      return true
    elsif manager_orgs.length > 0
      return true if include_admin_managers && admin_manager?(manager)
      if user_orgs.length > 0
        # check for any user orgs higher in the hierarchy
        more_user_record_codes = user_orgs.dup
        last_user_record_codes = []
        while last_user_record_codes.length != more_user_record_codes.length
          last_user_record_codes = more_user_record_codes.dup
          orgs = Organization.find_all_by_global_id(more_user_record_codes.map{|c| c.split(/:/)[1] })
          parent_ids = orgs.map{|o| o.parent_org_id }.compact.uniq
          more_user_record_codes += parent_ids.map{|id| "Organization:#{id}" }
          more_user_record_codes.uniq!
        end
        return true if (manager_orgs & more_user_record_codes).length > 0
      end
    end
    return true if include_admin_managers && admin_manager?(manager)
    return false
  end
  
  def touch_parent
    return unless self.parent_organization_id
    Organization.where(id: self.parent_organization_id).update_all(updated_at: Time.now)
    true
  end
  
  def parent_org_id
    return nil unless self.parent_organization_id
    self.related_global_id(self.parent_organization_id)
  end
  
  def upstream_orgs
    return [] unless self.parent_organization_id
    org_ids = []
    org = self
    while org && org.parent_org_id && !org_ids.include?(org.parent_org_id)
      org = Organization.find_by_global_id(org.parent_org_id)
      org_ids << org.global_id if org
      org_ids.uniq!
    end
    Organization.find_all_by_global_id(org_ids - [self.global_id])
  end
  
  def has_children?
    cache_key = "org/has_children/#{self.global_id}/#{self.updated_at.to_f}"
    cached_data = JSON.parse(Permissable.permissions_redis.get(cache_key)) rescue nil
    return cached_data['result'] if cached_data != nil
    # TODO: sharding
    res = Organization.where(parent_organization_id: self.id).count > 0
    expires = 72.hours.to_i
    Permissable.permissions_redis.setex(cache_key, expires, {result: res}.to_json)
    res
  end
  
  def children_orgs
    return [] unless self.has_children?
    # TODO: sharding
    Organization.where(parent_organization_id: self.id)
  end
  
  def downstream_orgs
    return [] unless self.has_children?
    list = [self]
    last_list = []
    while list.length != last_list.length
      last_list = list.dup
      list += list.map(&:children_orgs).flatten.compact
      list.uniq!
    end
    list - [self]
  end
  
  def self.admin_manager?(manager)
    manager_orgs = UserLink.links_for(manager).select{|l| l['type'] == 'org_manager' && l['user_id'] == manager.global_id && l['state']['full_manager'] }.map{|l| l['record_code'] }
    
    if manager_orgs.length > 0
      # if manager is part of the global org (the order of lookups seems weird, but should be a little more efficient)
      org = self.admin
      return true if org && manager_orgs.include?(Webhook.get_record_code(org))
    end
    false
  end
  
  def detach_user(user, user_type)
    user_types = [user_type]
    UserLink.remove(user, self, "org_#{user_type}")
    key = nil
    if user_type == 'user'
      user_types += ['sponsored_user', 'approved_user', 'eval_user']
      key = 'managed_by'
    elsif user_type == 'supervisor'
      key = 'supervisor_for'
    elsif user_type == 'manager'
      key = 'manager_for'
    end
    if key && user.settings[key] && user.settings[key][self.global_id]
      user.settings[key].delete(self.global_id)
      user.save
    end
    user_types.each do |type|
      self.settings['attached_user_ids'] ||= {}
      self.settings['attached_user_ids'][type] ||= []
      self.settings['attached_user_ids'][type].select!{|id| id != user.global_id }
    end
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
    links = UserLink.links_for(self)
    if user_type == 'user'
      links = links.select{|l| l['type'] == 'org_user' && !l['state']['eval'] }
    elsif user_type == 'manager'
      links = links.select{|l| l['type'] == 'org_manager' }
    elsif user_type == 'supervisor'
      links = links.select{|l| l['type'] == 'org_supervisor' }
    elsif user_type == 'eval'
      links = links.select{|l| l['type'] == 'org_user' && l['state']['eval'] }
    elsif user_type == 'subscription'
      links = links.select{|l| l['type'] == 'org_subscription' }
    elsif user_type == 'approved_user'
      links = links.select{|l| l['type'] == 'org_user' && !l['state']['pending'] }
    elsif user_type == 'sponsored_user'
      links = links.select{|l| l['type'] == 'org_user' && l['state']['sponsored'] }
    else
      raise "unrecognized type, #{user_type}"
    end
    user_ids = links.map{|l| l['user_id'] }.uniq
    User.where(:id => User.local_ids(user_ids))
  end
  
  def users
    self.attached_users('user')
  end
  
  def sponsored_users(chainable=true)
    # TODO: get rid of this double-lookup
    users = self.attached_users('user').select{|u| self.sponsored_user?(u) }
    if chainable
      User.where(:id => users.map(&:id))
    else
      users
    end
  end

  def eval_users(chainable=true)
    # TODO: get rid of this double-lookup
    users = self.attached_users('eval')
    if chainable
      User.where(:id => users.map(&:id))
    else
      users
    end
  end
  
  def approved_users(chainable=true)
    # TODO: get rid of this double-lookup
    users = self.attached_users('user').select{|u| !self.pending_user?(u) }
    if chainable
      User.where(:id => users.map(&:id))
    else
      users
    end
  end
  
  def managers
    self.attached_users('manager')
  end
  
  def evals
    self.attached_users('eval')
  end
  
  def supervisors
    self.attached_users('supervisor')
  end  
  
  def subscriptions
    self.attached_users('subscription')
  end
  
  def self.attached_orgs(user, include_org=false)
    links = UserLink.links_for(user)
    org_ids = []
    links.each do |link|
      if link['type'] == 'org_user' || link['type'] == 'org_manager' || link['type'] == 'org_supervisor'
        org_ids << link['record_code'].split(/:/)[1]
      end
    end
    res = []
    orgs = {}
    Organization.find_all_by_global_id(org_ids.uniq).each do |org|
      orgs[Webhook.get_record_code(org)] = org
    end
    links.each do |link|
      org = orgs[link['record_code']]
      if link['type'] == 'org_user' && org
        e = {
          'id' => org.global_id,
          'name' => org.settings['name'],
          'type' => 'user',
          'added' => link['state']['added'],
          'pending' => !!link['state']['pending'],
          'sponsored' => !!link['state']['sponsored']
        }
        e['org'] = org if include_org
        res << e
      elsif link['type'] == 'org_manager' && org
        e = {
          'id' => org.global_id,
          'name' => org.settings['name'],
          'type' => 'manager',
          'added' => link['state']['added'],
          'full_manager' => !!link['state']['full_manager'],
          'admin' => !!org.admin
        }
        e['org'] = org if include_org
        res << e
      elsif link['type'] == 'org_supervisor' && org
        e = {
          'id' => org.global_id,
          'name' => org.settings['name'],
          'type' => 'supervisor',
          'added' => link['state']['added'],
          'pending' => !!link['state']['pending']
        }
        e['org'] = org if include_org
        res << e
      end
    end
    res
  end
  
  def user?(user)
    managed_user?(user)
  end
  
  def add_user(user_key, pending, sponsored=true, eval_account=false)
    user = User.find_by_path(user_key)
    raise "invalid user, #{user_key}" unless user
    raise "invalid settings" if eval_account && !sponsored
    # for_different_org ||= user.settings && user.settings['managed_by'] && (user.settings['managed_by'].keys - [self.global_id]).length > 0
    # raise "already associated with a different organization" if for_different_org
    if eval_account
      sponsored_eval_count = self.eval_users(false).count
      raise "no eval licenses available" if sponsored && ((self.settings || {})['total_eval_licenses'] || 0) <= sponsored_eval_count
    else
      sponsored_user_count = self.sponsored_users(false).count
      raise "no licenses available" if sponsored && ((self.settings || {})['total_licenses'] || 0) <= sponsored_user_count
    end
    user.update_subscription_organization(self, pending, sponsored, eval_account)
    true
  end
  
  def remove_user(user_key)
    user = User.find_by_path(user_key)
    raise "invalid user, #{user_key}" unless user
    pending = !!UserLink.links_for(user).detect{|l| l['type'] == 'org_user' && l['record_code'] == Webhook.get_record_code(self) && l['state']['pending'] }
    user.update_subscription_organization("r#{self.global_id}")
    notify('org_removed', {
      'user_id' => user.global_id,
      'user_type' => 'user',
      'removed_at' => Time.now.iso8601
    }) unless pending
    OrganizationUnit.schedule(:remove_as_member, user_key, 'communicator', self.global_id)
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
  
  def self.usage_stats(approved_users, admin=false)
    sessions = LogSession.where(['started_at > ?', 4.months.ago]).where({log_type: 'session'})
    res = {
      'weeks' => [],
      'user_counts' => {}
    }

    if !admin
      # TODO: sharding
      sessions = sessions.where(:user_id => approved_users.map(&:id))
    end

    res['user_counts']['goal_set'] = approved_users.select{|u| !!u.settings['primary_goal'] }.length
    two_weeks_ago_iso = 2.weeks.ago.iso8601
    res['user_counts']['goal_recently_logged'] = approved_users.select{|u| u.settings['primary_goal'] && u.settings['primary_goal']['last_tracked'] && u.settings['primary_goal']['last_tracked'] > two_weeks_ago_iso }.length
    
    recent = sessions.where(['started_at > ?', 2.weeks.ago])
    res['user_counts']['recent_session_count'] = recent.count
    res['user_counts']['recent_session_seconds'] = recent.sum('EXTRACT(epoch FROM (ended_at - started_at))')
    res['user_counts']['recent_session_hours'] = (res['user_counts']['recent_session_seconds'] / 3600.0).round(2)
    res['user_counts']['recent_session_user_count'] = recent.distinct.count('user_id')
    res['user_counts']['total_users'] = approved_users.count
    
    
    sessions.group("date_trunc('week', started_at)").select("date_trunc('week', started_at)", "SUM(EXTRACT(epoch FROM (ended_at - started_at)))", "COUNT(*)").sort_by{|s| s.date_trunc }.each do |s|
      date = s.date_trunc
      count = s.count
      sum = s.sum
      if date && date < Time.now
        res['weeks'] << {
          'timestamp' => date.to_time.to_i,
          'session_seconds' => sum,
          'sessions' => count
        }
      end
    end
    res
  end
  
  def process_params(params, non_user_params)
    self.settings ||= {}
    self.settings['name'] = process_string(params['name']) if params['name']
    raise "updater required" unless non_user_params['updater']
    if params[:allotted_licenses]
      total = params[:allotted_licenses].to_i
      used = self.sponsored_users(false).count
      if total < used
        add_processing_error("too few licenses, remove some users first")
        return false
      end
      if self.settings['total_licenses'] != total
        self.settings['total_licenses'] = total
        self.log_purchase_event({
          'type' => 'update_license_count',
          'count' => total,
          'updater_id' => non_user_params['updater'].global_id,
          'updater_user_name' => non_user_params['updater'].user_name
        }, false)
      end
    end
    if params[:allotted_eval_licenses]
      total = params[:allotted_eval_licenses].to_i
      used = self.eval_users(false).count
      if total < used
        add_processing_error("too few eval licenses, remove some users first")
        return false
      end
      if self.settings['total_eval_licenses'] != total
        self.settings['total_eval_licenses'] = total
        self.log_purchase_event({
          'type' => 'update_eval_license_count',
          'count' => total,
          'updater_id' => non_user_params['updater'].global_id,
          'updater_user_name' => non_user_params['updater'].user_name
        }, false)
      end
    end
    self.settings['include_extras'] = params[:include_extras] unless params[:include_extras] == nil
    if params[:licenses_expire]
      time = Time.parse(params[:licenses_expire])
      self.settings['licenses_expire'] = time.iso8601
    end
    
    if params[:home_board_key]
      key = params[:home_board_key]
      if key.match(/^https?:\/\/[^\/]+\//)
        key = key.sub(/^https?:\/\/[^\/]+\//, '')
      end
    
      board = Board.find_by_path(key)
      if board && board.public
        self.settings['default_home_board'] = {
          'id' => board.global_id,
          'key' => board.key
        }
      elsif board
        management_ids = self.managers.map(&:global_id) + self.supervisors.map(&:global_id)
        # if any of the managers or supervisors own the board, then it's ok
        if management_ids.include?(board.user.global_id)
          self.settings['default_home_board'] = {
            'id' => board.global_id,
            'key' => board.key
          }
        end
      end
    end
    
    if params[:management_action]
      if !self.id
        add_processing_error("can't manage users on create") 
        return false
      end

      action, key = params[:management_action].split(/-/, 2)
      begin
        if action == 'add_user'
          self.add_user(key, true, true, false)
        elsif action == 'add_unsponsored_user'
          self.add_user(key, true, false, false)
        elsif action == 'add_eval'
          self.add_user(key, true, true, true)
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
    @processed = true
    true
  end
end
