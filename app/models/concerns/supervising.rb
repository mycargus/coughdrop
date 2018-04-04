module Supervising
  extend ActiveSupport::Concern
  
  def generate_link_code
    return nil unless self.premium?
    code = GoSecure.nonce('link_code')[0, 5]
    self.settings['link_codes'] ||= []
    self.settings['link_codes'].select!{|c| id, nonce, ts = c.split(/-/, 3); Time.at(ts.to_i) > 6.hours.ago }
    code = "#{self.global_id}-#{code}-#{Time.now.to_i}"
    self.settings['link_codes'] << code
    self.save
    code
  end
  
  def link_to_supervisee_by_code(code)
    return false unless code
    id, nonce, ts = code.split(/-/, 3)
    user = User.find_by_global_id(id)
    user = nil unless user && user.premium? &&
        (user.settings['link_codes'] || []).include?(code) && 
        Time.at(ts.to_i) > 6.hours.ago
    return false unless user && user != self
    supervisors = User.find_all_by_global_id(user.supervisor_user_ids)
    non_premium_supervisors = supervisors.select{|u| !u.premium? }
    return false if non_premium_supervisors.length >= 5
    self.save unless self.id
    self.class.link_supervisor_to_user(self, user, code)
    true
  end
  
  def supervisor_user_ids
    sups = UserLink.links_for(self).select{|l| l['type'] == 'supervisor' && l['user_id'] == self.global_id}
    sups.map{|l| l['record_code'].split(/:/)[1] }.uniq
  end
  
  def supervisor_links
    return [] unless self.id
    UserLink.links_for(self).select{|l| l['type'] == 'supervisor' && l['user_id'] == self.global_id }
  end
  
  def supervisor_for?(user)
    user.supervisor_user_ids.include?(self.global_id) || Organization.manager_for?(self, user)
  end
  
  def supervisors
    if !self.supervisor_user_ids.blank?
      User.find_all_by_global_id(self.supervisor_user_ids)
    else
      []
    end
  end
  
  def managing_organization
    orgs = Organization.attached_orgs(self)
    org = orgs.detect{|o| o['type'] == 'user' && !o['pending'] && o['sponsored'] }
    org ||= orgs.detect{|o| o['type'] == 'user' && !o['pending'] }
    org ||= orgs.detect{|o| o['type'] == 'user' }
    if org
      Organization.find_by_global_id(org['id'])
    else
      nil
    end
  end
  
  def organization_hash
    res = []
    res += Organization.attached_orgs(self)
    res.reverse.uniq{|e| [e['id'], e['type']] }.sort_by{|e| e['id'] }
  end

  def supervisee_links
    return [] unless self.id
    code = Webhook.get_record_code(self)
    UserLink.links_for(self).select{|l| l['type'] == 'supervisor' && l['record_code'] == code }
  end
  
  def supervised_user_ids
    supervisee_links.map{|l| l['user_id'] }.compact.uniq
  end
  
  def supervisees
    if !self.supervised_user_ids.blank?
      User.find_all_by_global_id(self.supervised_user_ids).sort_by(&:user_name)
    else
      []
    end
  end
  
  def edit_permission_for?(supervisee)
    sup = supervisee.supervisor_links.any?{|l| l['record_code'] == Webhook.get_record_code(self) && l['user_id'] == supervisee.global_id && l['state']['edit_permission'] } 
    sup || Organization.manager_for?(self, user)
  end

  def org_units_for_supervising(supervisee)
    unit_ids = supervisee_links.map{|l| l['state']['organization_unit_ids'] }.compact.flatten.uniq
    OrganizationUnit.find_all_by_global_id(unit_ids)
  end
  
  def process_supervisor_key(key)
    action, key = key.split(/-/, 2)
    if action == 'add' || action == 'add_edit'
      return false unless self.premium? && self.id
      supervisor = User.find_by_path(key)
      if key.match(/@/)
        users = User.find_by_email(key)
        if users.length == 1
          supervisor = users[0]
        end
      end
      return false if !supervisor || self == supervisor
      self.class.link_supervisor_to_user(supervisor, self, nil, action == 'add_edit')
      return true
    elsif action == 'approve' && key == 'org'
      self.settings['pending'] = false
      self.update_subscription_organization(self.managing_organization.global_id, false, nil, nil)
      true
    elsif action == 'approve_supervision'
      org = Organization.find_by_global_id(key)
      if org.pending_supervisor?(self)
        org.approve_supervisor(self)
        true
      elsif org.supervisor?(self)
        true
      else
        false
      end
    elsif action == 'remove_supervision'
      org = Organization.find_by_global_id(key)
      org.reject_supervisor(self)
      true
    elsif action == 'remove_supervisor'
      if key.match(/^org/)
        org_id = key.split(/-/)[1]
        org_id ||= self.managing_organization.global_id
        self.update_subscription_organization("r#{org_id}")
      else
        supervisor = User.find_by_path(key)
        user = self
        return false unless supervisor && user
        self.class.unlink_supervisor_from_user(supervisor, user)
      end
      true
    elsif action == 'remove_supervisee'
      supervisor = self
      user = User.find_by_path(key)
      return false unless supervisor && user
      self.class.unlink_supervisor_from_user(supervisor, user)
    else
      return false
    end
  end
  
  def remove_supervisors!
    user = self
    self.supervisors.each do |sup|
      User.unlink_supervisor_from_user(sup, user)
    end
  end
  
  module ClassMethods  
    def unlink_supervisor_from_user(supervisor, user, organization_unit_id=nil)
      supervisor = user if supervisor.global_id == user.global_id
      sup = (user.settings['supervisors'] || []).detect{|s| s['user_id'] == supervisor.global_id }
      org_unit_ids = (sup || {})['organization_unit_ids'] || []
      org_unit_ids += UserLink.links_for(user).select{|l| l['type'] == 'supervisor' && l['user_id'] == user.global_id && l['record_code'] == Webhook.get_record_code(supervisor) }.map{|l| l['state'] && l['state']['organization_unit_ids'] }.compact.flatten
      org_unit_ids.uniq!
      
      user.settings['supervisors'] = (user.settings['supervisors'] || []).select{|s| s['user_id'] != supervisor.global_id }
      do_unlink = true
      if organization_unit_id && (org_unit_ids - [organization_unit_id]).length > 0
        org_unit_ids -= [organization_unit_id]
        link = UserLink.generate(user, supervisor, 'supervisor')
        link.data['state']['organization_unit_ids'] = org_unit_ids
        link.save!
        do_unlink = false
      else
        UserLink.remove(user, supervisor, 'supervisor')
      end
      user.update_setting({
        'supervisors' => user.settings['supervisors']
      })
      user.reload
      if do_unlink
        supervisor.reload
        supervisor.settings['supervisees'] = (supervisor.settings['supervisees'] || []).select{|s| s['user_id'] != user.global_id }
        # If a user was auto-subscribed for being added as a supervisor, un-subscribe them when removed
        if supervisor.settings['supervisees'].empty? && supervisor.settings && supervisor.settings['subscription'] && supervisor.settings['subscription']['subscription_id'] == 'free_auto_adjusted'
          supervisor.update_subscription({
            'unsubscribe' => true,
            'subscription_id' => 'free_auto_adjusted',
            'plan_id' => 'slp_monthly_free'
          })
        end
        supervisor.schedule_once(:update_available_boards)
        supervisor.update_setting({
          'supervisees' => supervisor.settings['supervisees']
        })
      end
    end
    
    def link_supervisor_to_user(supervisor, user, code=nil, editor=true, organization_unit_id=nil)
      # raise "free_premium users can't add supervisors" if user.free_premium?
      supervisor = user if supervisor.global_id == user.global_id
      
      org_unit_ids = ((user.settings['supervisors'] || []).detect{|s| s['user_id'] == supervisor.global_id } || {})['organization_unit_ids'] || []
      org_unit_ids += UserLink.links_for(user).select{|l| l['type'] == 'supervisor' && l['record_code'] == Webhook.get_record_code(supervisor) }.map{|l| l['state'] && l['state']['organization_unit_ids'] }.compact.flatten

      link = UserLink.generate(user, supervisor, 'supervisor')
      link.data['state']['edit_permission'] = true if editor
      link.data['state']['supervisee_user_name'] = user.user_name
      link.data['state']['supervisor_user_name'] = supervisor.user_name
      link.data['state']['organization_unit_ids'] = ((org_unit_ids || []) + ([organization_unit_id].compact)).uniq
      link.secondary_user_id = supervisor.id
      link.save!


#      user.settings['supervisors'] = (user.settings['supervisors'] || []).select{|s| s['user_id'] != supervisor.global_id }
#       sup = {
#         'user_id' => supervisor.global_id,
#         'user_name' => supervisor.user_name,
#         'edit_permission' => editor,
#         'organization_unit_ids' => org_unit_ids
#       }
#       if organization_unit_id
#         sup['organization_unit_ids'] << organization_unit_id 
#         sup['organization_unit_ids'].uniq!
#       end
#       user.settings['supervisors'] << sup
#       user.settings['link_codes'] -= [code] if code
#       user.update_setting({
#         'supervisors' => user.settings['supervisors'],
#         'link_codes' => user.settings['link_codes']
#       })

      supervisor.reload
      # first-time supervisors should automatically be set to the supporter role
      if !supervisor.settings['supporter_role_auto_set']
        supervisor.settings['supporter_role_auto_set'] = true
        supervisor.settings['preferences']['role'] = 'supporter'
      end
      # If a user is on a free trial and they're added as a supervisor, set them to a free supporter subscription
      if supervisor.grace_period?
        supervisor.update_subscription({
          'subscribe' => true,
          'subscription_id' => 'free_auto_adjusted',
          'token_summary' => "Automatically-set Supporter Account",
          'plan_id' => 'slp_monthly_free'
        })
      end
#       supervisor.settings['supervisees'] = (supervisor.settings['supervisees'] || []).select{|s| s['user_id'] != user.global_id }
#       supervisor.settings['supervisees'] << {
#         'user_id' => user.global_id,
#         'user_name' => user.user_name,
#         'edit_permission' => editor
#       }
#       supervisor.update_setting({
#         'supervisees' => supervisor.settings['supervisees']
#       })
      supervisor.schedule_once(:update_available_boards)
      user.save
      supervisor.save
    end
  end
end