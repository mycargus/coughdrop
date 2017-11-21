class UserLink < ApplicationRecord
  include Permissions
  include Async
  include GlobalId
  include SecureSerialize
  
  belongs_to :user
  secure_serialize :data

  before_save :generate_defaults
  after_save :touch_connections
  after_destroy :touch_connections

  def generate_defaults
    self.data ||= {}
  end
  
  def touch_connections
    # TODO: sharding
    User.where(id: [self.user_id, self.secondary_user_id].compact).update_all(updated_at: Time.now)
    r = self.record
    if r
      # TODO: sharding
      r.class.where(id: r.id).update_all(updated_at: Time.now)
    end
    true
  end
  
  def record
    return nil unless self.record_code
    Webhook.find_record(self.record_code)
  end
  
  def self.generate(user, record, type, state=nil)
    record_code = Webhook.get_record_code(record)
    links = UserLink.where(user_id: user.id, record_code: record_code)
    res = links.detect{|l| l.data['type'] == type}
    res ||= UserLink.new
    res.user = user
    res.record_code = Webhook.get_record_code(record)
    res.data ||= {}
    res.data['type'] = type
    res.data['state'] = state if state
    res.data['state'] ||= {}
    res
  end
  
  def self.remove(user, record, type)
    record_code = Webhook.get_record_code(record)
    links = UserLink.where(user_id: user.id, record_code: record_code)
    links = links.select{|l| l.data['type'] == type }
    links.each{|l| l.destroy }
    true
  end
  
  def self.links_for(record, force=false)
    return [] unless record && record.id
    record_code = Webhook.get_record_code(record)
    cache_string = Permissable.permissions_redis.get("links/for/#{record_code}/#{record.updated_at}")
    if !force
      cache = nil
      if cache_string
        cache = JSON.parse(cache_string) rescue nil
      end
      return cache if cache
    end

    list = []
    if record.is_a?(User)
      # TODO: sharding
      list += self.where(user_id: record.id)
      list += self.where(secondary_user_id: record.id)
    end
    list += self.where(record_code: record_code)
    res = list.uniq.map do |link|
      {
        'user_id' => link.related_global_id(link.user_id),
        'record_code' => link.record_code,
        'type' => link.data['type'],
        'state' => link.data['state']
      }
    end
    if record.is_a?(User)
      # include old-school supervisors, supervisees, org connections, board shares
      (record.settings['boards_shared_with_me'] || []).each do |share|
        res << {
          'user_id' => record.global_id,
          'record_code' => "Board:#{share['board_id']}",
          'type' => 'board_share',
          'old_school' => true,
          'state' => {
            'include_downstream' => !!share['include_downstream'],
            'allow_editing' => !!share['allow_editing'],
            'pending' => !!share['pending'],
            'board_key' => share['board_key'],
            'user_name' => record.user_name
          }
        }
      end

      (record.settings['supervisors'] || []).each do |sup|
        res << {
          'user_id' => record.global_id,
          'record_code' => "User:#{sup['user_id']}",
          'type' => 'supervisor',
          'old_school' => true,
          'state' => {
            'edit_permission' => sup['edit_permission'],
            'organization_unit_ids' => sup['organization_unit_ids']
          }
        }
      end
      (record.settings['supervisees'] || []).each do |sup|
        res << {
          'user_id' => sup['user_id'],
          'record_code' => Webhook.get_record_code(record),
          'type' => 'supervisor',
          'old_school' => true,
          'state' => {
            'edit_permission' => sup['edit_permission'],
            'organization_unit_ids' => sup['organization_unit_ids']
          }
        }
      end
      org_ids = []
      (record.settings['managed_by'] || {}).each do |org_id, opts|
        org_ids << org_id
        res << {
          'user_id' => record.global_id,
          'record_code' => "Organization:#{org_id}",
          'type' => 'org_user',
          'old_school' => true,
          'state' => {
            'sponsored' => opts['sponsored'],
            'pending' => opts['pending']
          }
        }
      end
      (record.settings['manager_for'] || {}).each do |org_id, opts|
        org_ids << org_id
        res << {
          'user_id' => record.global_id,
          'record_code' => "Organization:#{org_id}",
          'type' => 'org_manager',
          'old_school' => true,
          'state' => {
            'full_manager' => opts['full_manager']
          }
        }
      end
      (record.settings['supervisor_for'] || {}).each do |org_id, opts|
        org_ids << org_id
        res << {
          'user_id' => record.global_id,
          'record_code' => "Organization:#{org_id}",
          'type' => 'org_supervisor',
          'old_school' => true,
          'state' => {
            'pending' => opts['pending']
          }
        }
      end
      if org_ids.length > 0
        possible_units = OrganizationUnit.where(:organization_id => record.class.local_ids(org_ids))
        possible_units.each do |unit|
          sup = (unit.settings['supervisors'] || []).detect{|s| s['user_id'] == record.global_id }
          comm = (unit.settings['communicators'] || []).detect{|c| c['user_id'] == record.global_id }
          if sup
            res << {
              'user_id' => record.global_id,
              'record_code' => Webhook.get_record_code(unit),
              'type' => 'org_unit_supervisor',
              'old_school' => true,
              'state' => {
                'edit_permission' => sup['edit_permission']
              }
            }
          end
          if comm
            res << {
              'user_id' => record.global_id,
              'record_code' => Webhook.get_record_code(unit),
              'type' => 'org_unit_communicator',
              'old_school' => true,
              'state' => {}
            }
          end
        end
      end
    elsif record.is_a?(Organization)
      # include org connections
      record.settings['attached_user_ids'].each do |type|
        type.each do |user_id|
          if type == 'user'
            sponsored = !!record.settings['attached_user_ids']['sponsored_user'].detect{|id| id == user_id }
            approved = !!record.settings['attached_user_ids']['approved_user'].detect{|id| id == user_id }
            res << {
              'user_id' => user_id,
              'record_code' => record_code,
              'type' => 'org_user',
              'old_school' => true,
              'state' => {
                'pending' => !approved,
                'sponsored' => sponsored
              }
            }
          elsif type == 'manager'
            res << {
              'user_id' => user_id,
              'record_code' => record_code,
              'type' => 'org_manager',
              'old_school' => true,
              'state' => {
                'full_manager' => true # TODO: this isn't always true...
              }
            }
          elsif type == 'supervisor'
            res << {
              'user_id' => user_id,
              'record_code' => record_code,
              'type' => 'org_supervisor',
              'old_school' => true,
              'state' => {}
            }
          elsif type == 'subscription'
            res << {
              'user_id' => user_id,
              'record_code' => record_code,
              'type' => 'org_subscription',
              'old_school' => true,
              'state' => {}
            }
          end
        end
      end
    elsif record.is_a?(OrganizationUnit)
      # include org unit connections
      (record.settings['supervisors'] || []).each do |sup|
        res << {
          'user_id' => sup['user_id'],
          'record_code' => record_code,
          'type' => 'org_unit_supervisor',
          'old_school' => true,
          'state' => {
            'user_name' => sup['user_name'],
            'edit_permission' => sup['edit_permission']
          }
        }
      end
      (record.settings['communicators'] || []).each do |com|
        res << {
          'user_id' => sup['user_id'],
          'record_code' => record_code,
          'type' => 'org_unit_communicator',
          'old_school' => true,
          'state' => {
            'user_name' => sup['user_name']
          }
        }
      end
    elsif record.is_a?(Board)
      # include board shares
      author = record.user
      if author
        shares = (author.settings['boards_i_shared'] || {})[record.global_id]
        (shares || []).each do |share|
          res << {
            'user_id' => share['user_id'],
            'record_code' => record_code,
            'type' => 'board_share',
            'old_school' => true,
            'state' => {
              'board_key' => record.key,
              'sharer_id' => author.global_id,
              'sharer_user_name' => author.user_name,
              'include_downstream' => share['include_downstream'],
              'allow_editing' => share['allow_editing'],
              'pending' => share['pending'],
              'user_name' => share['user_name']
            }
          }
        end
      end
    end
    
    expires = 72.hours.to_i
    Permissable.permissions_redis.setex(cache_string, expires, res.to_json)
    res
  end
  
  def self.assert_links(record)
    links = links_for(record, true).select{|l| l['old_school'] }
    links.each do |link|
      link_record = Webhook.find_record(link['record_code'])
      link_user = User.find_by_global_id(link['user_id'])
      if link_user && link_record
        generated = UserLink.generate(link_user, link_record, link['type'])
        generated['state'] ||= link['state']
        generated.save!
      end
      if record.is_a?(User)
        ['boards_shared_with_me', 'boards_i_shared', 'supervisors', 'supervisees', 'managed_by', 'manager_for', 'supervisor_for'].each do |key|
          record.settings["#{key}_old"] = record.settings[key] if record.settings[key]
          record.settings.delete(key)
        end
        record.save
      elsif record.is_a?(Board)
        
      elsif record.is_a?(Organization)
        record.settings['attached_user_ids_old'] = record.settings['attached_user_ids'] if record.settings['attached_user_ids']
        record.settings.delete('attached_user_ids')
        record.save
      elsif record.is_a?(OrganizationUnit)
        ['supervisors', 'communicators'].each do |key|
          record.settings["#{key}_old"] = record.settings[key] if record.settings[key]
          record.settings.delete(key)
        end
        record.save
      end
      
    end
    true
  end
end
