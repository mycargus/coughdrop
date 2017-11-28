class OrganizationUnit < ActiveRecord::Base
  include Permissions
  include Processable
  include GlobalId
  include Async
  include SecureSerialize
  secure_serialize :settings
  before_save :generate_defaults
  replicated_model  

  belongs_to :organization
  
  add_permissions('view', 'view_stats') {|user| self.supervisor?(user) }
  add_permissions('view', 'edit', 'delete') {|user| self.organization && self.organization.allows?(user, 'edit') }
  add_permissions('view', 'view_stats', 'edit', 'delete') {|user| self.organization && self.organization.allows?(user, 'manage') }
  
  def generate_defaults
    self.settings ||= {}
  end
  
  def process_params(params, non_user_params)
    self.organization ||= non_user_params[:organization]
    raise "organization required" unless self.organization
    self.settings ||= {}
    self.settings['name'] = process_string(params['name']) if params['name']
    if params['management_action'] && params['management_action'] != ''
      process_result = process_action(params['management_action']) 
      if !process_result
        add_processing_error("management_action was unsuccessful, #{params['management_action']}")
        return false
      end
    end
    true
  end
  
  def process_action(key)
    action, user_name = key.split(/-/, 2)
    if action == 'add_supervisor'
      add_supervisor(user_name, false)
    elsif action == 'add_edit_supervisor'
      add_supervisor(user_name, true)
    elsif action == 'remove_supervisor'
      remove_supervisor(user_name)
    elsif action == 'add_communicator'
      add_communicator(user_name)
    elsif action == 'remove_communicator'
      remove_communicator(user_name)
    else
      false
    end
  end
  
  def add_supervisor(user_name, edit_permission=false)
    user = User.find_by_path(user_name)
    org = self.organization
    return false unless user && org && org.supervisor?(user)
    link = UserLink.generate(user, self, 'org_unit_supervisor')
    link.data['state']['user_name'] = user.user_name
    link.data['state']['edit_permission'] = true if edit_permission
    link.save
#     assert_list('supervisors', user.global_id)
#     self.settings['supervisors'] << {
#       'user_id' => user.global_id,
#       'user_name' => user.user_name,
#       'edit_permission' => !!edit_permission
#     }
    self.schedule(:assert_supervision, {user_id: user.global_id, add_supervisor: user_name})
    true
#     self.save
  end
  
  def all_user_ids
    links = UserLink.links_for(self).select{|l| l['type'] == 'org_unit_supervisor' || l['type'] == 'org_unit_communicator' }
    links.map{|l| l['user_id'] }.uniq
  end
  
  def supervisor?(user)
    return false unless user
    links = UserLink.links_for(self).select{|l| l['type'] == 'org_unit_supervisor' }
    !!links.detect{|l| l['user_id'] == user.global_id }
  end
  
  def communicator?(user)
    return false unless user
    links = UserLink.links_for(self).select{|l| l['type'] == 'org_unit_communicator' }
    !!links.detect{|l| l['user_id'] == user.global_id }
  end
  
  def remove_supervisor(user_name)
    user = User.find_by_path(user_name)
    org = self.organization
    return false unless user && org
    UserLink.remove(user, self, 'org_unit_supervisor')
    assert_list('supervisors', user.global_id)
    schedule(:assert_supervision, {user_id: user.global_id, remove_supervisor: user_name})
    true
    self.save
  end
  
  def add_communicator(user_name)
    user = User.find_by_path(user_name)
    org = self.organization
    return false unless user && org && org.managed_user?(user) && !org.pending_user?(user)
    link = UserLink.generate(user, self, 'org_unit_communicator')
    link.data['state']['user_name'] = user.user_name
    link.save
#     assert_list('communicators', user.global_id)
#     self.settings['communicators'] << {
#       'user_id' => user.global_id,
#       'user_name' => user.user_name
#     }
    schedule(:assert_supervision, {user_id: user.global_id, add_communicator: user_name})
    true
#     self.save
  end
  
  def remove_communicator(user_name)
    user = User.find_by_path(user_name)
    org = self.organization
    return false unless user && org
    UserLink.remove(user, self, 'org_unit_communicator')
    assert_list('communicators', user.global_id)
    schedule(:assert_supervision, {user_id: user.global_id, remove_communicator: user_name})
    true
    self.save
  end
  
  def self.remove_as_member(user_name, member_type, organization_id)
    org = Organization.find_by_global_id(organization_id)
    # TODO: sharding
    OrganizationUnit.where(:organization_id => org.id).each do |unit|
      if member_type == 'supervisor'
        unit.remove_supervisor(user_name)
      elsif member_type == 'communicator'
        unit.remove_communicator(user_name)
      end
    end
  end
  
  def self.supervised_units(user)
    return [] unless user
    links = UserLink.links_for(user).select{|l| l['type'] == 'org_unit_supervisor' }
    ids = links.select{|l| l['user_id'] == user.global_id }.map{|l| ['record_code'].split(/:/)[1] }
    OrganizationUnit.find_all_by_global_id(ids).uniq
  end
  
  def assert_list(list, exclude_user_id)
    self.settings[list] = (self.settings[list] || []).select{|s| s['user_id'] != exclude_user_id }
  end
  
  def assert_supervision!
    links = UserLink.links_for(self)
    communicator_ids = links.select{|l| l['type'] == 'org_unit_communicator' }.map{|l| l['user_id'] }.uniq
    supervisor_links = links.select{|l| l['type'] == 'org_unit_supervisor' }
    supervisor_ids = supervisor_links.map{|l| l['user_id'] }.uniq
    communicators = User.find_all_by_global_id(communicator_ids)
    supervisors = User.find_all_by_global_id(supervisor_ids)
    supervisors.each do |sup|
      edit_permission = !!supervisor_links.detect{|l| l['user_id'] == sup.global_id && l['state'] && l['state']['edit_permission'] }
      communicators.each do |comm|
        User.link_supervisor_to_user(sup, comm, nil, !!edit_permission, self.global_id)
      end
    end
  end
  
  def assert_supervision(opts={})
    ref_user = User.find_by_path(opts['user_id'])
    return false unless ref_user

    links = UserLink.links_for(self)
    communicator_ids = links.select{|l| l['type'] == 'org_unit_communicator' }.map{|l| l['user_id'] }.uniq
    supervisor_links = links.select{|l| l['type'] == 'org_unit_supervisor' }
    supervisor_ids = supervisor_links.map{|l| l['user_id'] }.uniq
    communicators = User.find_all_by_global_id(communicator_ids)
    supervisors = User.find_all_by_global_id(supervisor_ids)

    if opts['remove_supervisor']
      communicators.each do |user|
        User.unlink_supervisor_from_user(ref_user, user, self.global_id)
      end
    elsif opts['remove_communicator']
      supervisors.each do |user|
        User.unlink_supervisor_from_user(user, ref_user, self.global_id)
      end
    elsif opts['add_supervisor']
      edit_permission = !!supervisor_links.detect{|l| l['user_id'] == ref_user.global_id && l['state'] && l['state']['edit_permission'] }
      communicators.each do |user|
        User.link_supervisor_to_user(ref_user, user, nil, edit_permission, self.global_id)
      end
    elsif opts['add_communicator']
      supervisors.each do |user|
        edit_permission = !!supervisor_links.detect{|l| l['user_id'] == user.global_id && l['state'] && l['state']['edit_permission'] }
        User.link_supervisor_to_user(user, ref_user, nil, edit_permission, self.global_id)
      end
    end
  end
end
