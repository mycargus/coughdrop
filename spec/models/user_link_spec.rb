require 'spec_helper'

describe UserLink, :type => :model do
  describe "touch_connections" do
    it "should touch all connected records on save" do
      u = User.create
      b = Board.create(user: u)
      User.all.update_all(updated_at: 2.weeks.ago)
      Board.all.update_all(updated_at: 2.weeks.ago)
      link = UserLink.generate(u, b, 'bacon')
      link.save
      expect(u.reload.updated_at).to be > 1.hour.ago
      expect(b.reload.updated_at).to be > 1.hour.ago
    end
    
    it "should touch all connected records on destroy" do
      u = User.create
      b = Board.create(user: u)
      User.all.update_all(updated_at: 2.weeks.ago)
      Board.all.update_all(updated_at: 2.weeks.ago)
      link = UserLink.generate(u, b, 'bacon')
      link.save
      expect(u.reload.updated_at).to be > 1.hour.ago
      expect(b.reload.updated_at).to be > 1.hour.ago

      User.all.update_all(updated_at: 2.weeks.ago)
      Board.all.update_all(updated_at: 2.weeks.ago)
      link.destroy
      expect(u.reload.updated_at).to be > 1.hour.ago
      expect(b.reload.updated_at).to be > 1.hour.ago
    end
  end
  
  describe "generate" do
    it "should assert the specified values" do
      u = User.create
      b = Board.create(user: u)
      link = UserLink.generate(u, b, 'bacon')
      expect(link.user).to eq(u)
      expect(link.record_code).to eq(Webhook.get_record_code(b))
      expect(link.data['type']).to eq('bacon')
    end
    
    it "should set state if defined" do
      u = User.create
      b = Board.create(user: u)
      link = UserLink.generate(u, b, 'bacon', {a: 1, b: 2})
      expect(link.user).to eq(u)
      expect(link.record_code).to eq(Webhook.get_record_code(b))
      expect(link.data['type']).to eq('bacon')
      expect(link.data['state']).to eq({a: 1, b: 2})
    end
    
    it "should assert state if not defined" do
      u = User.create
      b = Board.create(user: u)
      link = UserLink.generate(u, b, 'bacon')
      expect(link.user).to eq(u)
      expect(link.record_code).to eq(Webhook.get_record_code(b))
      expect(link.data['type']).to eq('bacon')
      expect(link.data['state']).to eq({})
    end
  end

  describe "remove" do
    it "should remove the specified record, if any" do
      u = User.create
      b = Board.create(user: u)
      link = UserLink.generate(u, b, 'bacon')
      link.save
      expect(UserLink.count).to eq(1)

      UserLink.remove(u, b, 'something')
      expect(UserLink.count).to eq(1)
      
      UserLink.remove(User.create, b, 'bacon')
      expect(UserLink.count).to eq(1)
      
      UserLink.remove(u, Board.create(user: u), 'bacon')
      expect(UserLink.count).to eq(1)
      
      UserLink.remove(u, b, 'bacon')
      expect(UserLink.count).to eq(0)
    end
  end

  describe "links_for" do
    it "should include both old and new user links" do
      u = User.create
      u2 = User.create
      b = Board.create(user: u)
      o = Organization.create
      ou = OrganizationUnit.create(organization: o)
      ou.settings['supervisors'] = [
        {},
        {'user_id' => u.global_id, 'edit_permission' => true}
      ]
      ou.settings['communicators'] = [
        {'user_id' => u.global_id}
      ]
      ou.save
      link = UserLink.generate(u, b, 'bacon')
      link.save
      u.settings['boards_shared_with_me'] = [{
        'board_id' => '1_12345',
        'include_downstream' => true,
        'allow_editing' => true,
        'pending' => true,
        'board_key' => 'a/b'
      }]
      u.settings['supervisors'] = [{
        'user_id' => u2.global_id,
        'edit_permission' => true, 
        'organization_unit_ids' => ['a', 'b']
      }]
      u.settings['supervisees'] = [{
        'user_id' => u2.global_id,
        'edit_permission' => true,
        'organization_unit_ids' => ['c', 'd']
      }]
      u.settings['managed_by'] = {}
      u.settings['managed_by'][o.global_id] = {
        'sponsored' => true,
        'pending' => true
      }
      u.settings['manager_for'] = {}
      u.settings['manager_for'][o.global_id] = {
        'full_manager' => true
      }
      u.settings['supervisor_for'] = {}
      u.settings['supervisor_for'][o.global_id] = {
        'pending' => true
      }
      u.save
      expect(UserLink.links_for(u)).to eq([
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(b),
          'type' => 'bacon', 
          'state' => {}
        },
        {
          'user_id' => u.global_id,
          'record_code' => 'Board:1_12345',
          'type' => 'board_share',
          'old_school' => true,
          'state' => {
            'include_downstream' => true,
            'allow_editing' => true,
            'pending' => true,
            'board_key' => 'a/b',
            'user_name' => u.user_name
          }
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(u2),
          'type' => 'supervisor',
          'old_school' => true,
          'state' => {
            'edit_permission' => true,
            'organization_unit_ids' => ['a', 'b']
          }
        },
        {
          'user_id' => u2.global_id,
          'record_code' => Webhook.get_record_code(u),
          'type' => 'supervisor',
          'old_school' => true,
          'state' => {
            'edit_permission' => true,
            'organization_unit_ids' => ['c', 'd']
          }
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_user',
          'old_school' => true,
          'state' => {
            'sponsored' => true,
            'pending' => true
          }
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_manager',
          'old_school' => true,
          'state' => {
            'full_manager' => true
          }
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_supervisor',
          'old_school' => true,
          'state' => {
            'pending' => true
          }
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(ou),
          'type' => 'org_unit_supervisor',
          'old_school' => true,
          'state' => {
            'edit_permission' => true
          }
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(ou),
          'type' => 'org_unit_communicator',
          'old_school' => true, 
          'state' => {}
        }
      ])
    end

    it "should include both old and new org links" do
      u = User.create
      u2 = User.create
      u3 = User.create
      u4 = User.create
      o = Organization.create
      o.settings['attached_user_ids'] = {
        'user' => [u.global_id, u2.global_id, u3.global_id],
        'sponsored_user' => [u.global_id],
        'approved_user' => [u.global_id, u2.global_id],
        'manager' => [u4.global_id],
        'supervisor' => [u4.global_id],
        'subscription' => [u4.global_id]
      }
      link = UserLink.generate(u, o, 'bacon')
      link.save
      expect(UserLink.links_for(o)).to eq([
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'bacon',
          'state' => {}
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_user',
          'old_school' => true,
          'state' => {
            'pending' => false,
            'sponsored' => true,
            'eval' => false
          }
        },
        {
          'user_id' => u2.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_user',
          'old_school' => true,
          'state' => {
            'pending' => false,
            'sponsored' => false,
            'eval' => false
          }
        },
        {
          'user_id' => u3.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_user',
          'old_school' => true,
          'state' => {
            'pending' => true,
            'sponsored' => false,
            'eval' => false
          }
        },
        {
          'user_id' => u4.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_manager',
          'old_school' => true,
          'state' => {
            'full_manager' => true
          }
        },
        {
          'user_id' => u4.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_supervisor',
          'old_school' => true,
          'state' => {
          }
        },
        {
          'user_id' => u4.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_subscription',
          'old_school' => true,
          'state' => {
          }
        }
      ])
    end
    
    it "should include both old and new board links" do
      u = User.create
      u2 = User.create
      u3 = User.create
      u4 = User.create
      b = Board.create(user: u)
      link = UserLink.generate(u, b, 'bacon')
      link.save
      b.share_with(u4, true, false)
      u.settings['boards_i_shared'] = {}
      u.settings['boards_i_shared'][b.global_id] = [
        {
          'user_id' => u2.global_id,
          'include_downstream' => true,
          'allow_editing' => true,
          'pending' => true,
          'user_name' => 'whatever'
        },
        {
          'user_id' => u3.global_id,
          'user_name' => 'bob'
        },
        {
          'user_id' => '11111',
          'user_name' => 'sally',
          'include_downstream' => false,
          'allow_editing' => false,
          'pending' => false
        }
      ]
      u.save
      expect(UserLink.links_for(b)).to eq([
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(b),
          'type' => 'bacon',
          'state' => {}
        },
        {
          'user_id' => u4.global_id,
          'record_code' => Webhook.get_record_code(b),
          'type' => 'board_share',
          'state' => {
            'board_key' => b.key,
            'sharer_id' => u.global_id,
            'sharer_user_name' => u.user_name,
            'include_downstream' => true,
            'pending' => false,
            'user_name' => u4.user_name
          }
        },
        {
          'user_id' => u2.global_id,
          'record_code' => Webhook.get_record_code(b),
          'type' => 'board_share',
          'old_school' => true,
          'state' => {
            'board_key' => b.key,
            'sharer_id' => u.global_id,
            'sharer_user_name' => u.user_name,
            'include_downstream' => true,
            'allow_editing' => true,
            'pending' => true,
            'user_name' => 'whatever'
          }
        },
        {
          'user_id' => u3.global_id,
          'record_code' => Webhook.get_record_code(b),
          'type' => 'board_share',
          'old_school' => true,
          'state' => {
            'board_key' => b.key,
            'sharer_id' => u.global_id,
            'sharer_user_name' => u.user_name,
            'include_downstream' => false,
            'allow_editing' => false,
            'pending' => false,
            'user_name' => 'bob'
          }
        },
        {
          'user_id' => '11111',
          'record_code' => Webhook.get_record_code(b),
          'type' => 'board_share',
          'old_school' => true,
          'state' => {
            'board_key' => b.key,
            'sharer_id' => u.global_id,
            'sharer_user_name' => u.user_name,
            'include_downstream' => false,
            'allow_editing' => false,
            'pending' => false,
            'user_name' => 'sally'
          }
        }
      ])
    end
    
    it "should include both old and new unit links" do
      o = Organization.create
      ou = OrganizationUnit.create(organization: o)
      u = User.create
      u2 = User.create
      ou.settings['supervisors'] = [{
        'user_id' => u.global_id,
        'user_name' => 'jobs',
        'edit_permission' => true
      }]
      ou.settings['communicators'] = [{
        'user_id' => u2.global_id,
        'user_name' => 'blech'
      }]
      link = UserLink.generate(u, ou, 'bacon')
      link.save
      expect(UserLink.links_for(ou)).to eq([
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(ou),
          'type' => 'bacon',
          'state' => {}
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(ou),
          'type' => 'org_unit_supervisor',
          'old_school' => true,
          'state' => {
            'user_name' => 'jobs',
            'edit_permission' => true
          }
        },
        {
          'user_id' => u2.global_id,
          'record_code' => Webhook.get_record_code(ou),
          'type' => 'org_unit_communicator',
          'old_school' => true,
          'state' => {
            'user_name' => 'blech'
          }
        }
      ])
    end
  end

  describe "assert_links" do
    it "should assert and remove old user links" do
      u = User.create
      u2 = User.create
      b = Board.create(user: u)
      o = Organization.create
      ou = OrganizationUnit.create(organization: o)
      ou.settings['supervisors'] = [
        {},
        {'user_id' => u.global_id, 'edit_permission' => true}
      ]
      ou.settings['communicators'] = [
        {'user_id' => u.global_id}
      ]
      ou.save
      link = UserLink.generate(u, b, 'bacon')
      link.save
      u.settings['boards_i_shared'] = []
      u.settings['boards_shared_with_me'] = [{
        'board_id' => b.global_id,
        'include_downstream' => true,
        'allow_editing' => true,
        'pending' => true,
        'board_key' => 'a/b'
      },
      {
        'board_id' => '12345',
        'include_downstream' => true,
        'allow_editing' => true,
        'pending' => true,
        'board_key' => 'a/b'
      }]
      u.settings['supervisors'] = [{
        'user_id' => u2.global_id,
        'edit_permission' => true, 
        'organization_unit_ids' => ['a', 'b']
      }]
      u.settings['supervisees'] = [{
        'user_id' => u2.global_id,
        'edit_permission' => true,
        'organization_unit_ids' => ['c', 'd']
      }]
      u.settings['managed_by'] = {}
      u.settings['managed_by'][o.global_id] = {
        'sponsored' => true,
        'pending' => true
      }
      u.settings['manager_for'] = {}
      u.settings['manager_for'][o.global_id] = {
        'full_manager' => true
      }
      u.settings['supervisor_for'] = {}
      u.settings['supervisor_for'][o.global_id] = {
        'pending' => true
      }
      u.save
      expect(UserLink.links_for(u).length).to eq(10)
      expect(UserLink.assert_links(u)).to eq(true)
      expect(UserLink.links_for(u.reload).length).to eq(9)
      expect(UserLink.links_for(u.reload).sort_by{|l| [l['type'], l['user_id'], l['record_code']] }).to eq([
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(b),
          'type' => 'bacon', 
          'state' => {}
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(b),
          'type' => 'board_share',
          'state' => {
            'include_downstream' => true,
            'allow_editing' => true,
            'pending' => true,
            'board_key' => 'a/b',
            'user_name' => u.user_name
          }
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_manager',
          'state' => {
            'full_manager' => true
          }
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_supervisor',
          'state' => {
            'pending' => true
          }
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(ou),
          'type' => 'org_unit_communicator',
          'state' => {}
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(ou),
          'type' => 'org_unit_supervisor',
          'state' => {
            'edit_permission' => true
          }
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_user',
          'state' => {
            'sponsored' => true,
            'pending' => true
          }
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(u2),
          'type' => 'supervisor',
          'state' => {
            'edit_permission' => true,
            'organization_unit_ids' => ['a', 'b']
          }
        },
        {
          'user_id' => u2.global_id,
          'record_code' => Webhook.get_record_code(u),
          'type' => 'supervisor',
          'state' => {
            'edit_permission' => true,
            'organization_unit_ids' => ['c', 'd']
          }
        },
      ])

      ['boards_shared_with_me', 'boards_i_shared', 'supervisors', 'supervisees', 'managed_by', 'manager_for', 'supervisor_for'].each do |key|
        expect(u.settings[key]).to eq(nil)
        expect(u.settings["#{key}_old"]).to_not eq(nil)
      end
    end
    
    it "should assert and remove old org links" do
      u = User.create
      u2 = User.create
      u3 = User.create
      u4 = User.create
      o = Organization.create
      o.settings['attached_user_ids'] = {
        'user' => [u.global_id, u2.global_id, u3.global_id],
        'sponsored_user' => [u.global_id],
        'approved_user' => [u.global_id, u2.global_id],
        'manager' => [u4.global_id],
        'supervisor' => [u4.global_id],
        'subscription' => [u4.global_id]
      }
      link = UserLink.generate(u, o, 'bacon')
      link.save
      expect(UserLink.links_for(o).length).to eq(7)
      expect(UserLink.assert_links(o)).to eq(true)
      expect(UserLink.links_for(o.reload).length).to eq(7)
      expect(UserLink.links_for(o).sort_by{|l| [l['type'], l['user_id'], l['record_code']] }).to eq([
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'bacon',
          'state' => {}
        },
        {
          'user_id' => u4.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_manager',
          'state' => {
            'full_manager' => true
          }
        },
        {
          'user_id' => u4.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_subscription',
          'state' => {
          }
        },
        {
          'user_id' => u4.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_supervisor',
          'state' => {
          }
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_user',
          'state' => {
            'pending' => false,
            'sponsored' => true,
            'eval' => false
          }
        },
        {
          'user_id' => u2.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_user',
          'state' => {
            'pending' => false,
            'sponsored' => false,
            'eval' => false
          }
        },
        {
          'user_id' => u3.global_id,
          'record_code' => Webhook.get_record_code(o),
          'type' => 'org_user',
          'state' => {
            'pending' => true,
            'sponsored' => false,
            'eval' => false
          }
        },
      ])
    end
    
    it "should assert and remove old unit links" do
      o = Organization.create
      ou = OrganizationUnit.create(organization: o)
      u = User.create
      u2 = User.create
      ou.settings['supervisors'] = [{
        'user_id' => u.global_id,
        'user_name' => 'jobs',
        'edit_permission' => true
      }]
      ou.settings['communicators'] = [{
        'user_id' => u2.global_id,
        'user_name' => 'blech'
      }]
      link = UserLink.generate(u, ou, 'bacon')
      link.save
      expect(UserLink.links_for(ou).length).to eq(3)
      expect(UserLink.assert_links(ou)).to eq(true)
      expect(UserLink.links_for(ou.reload).length).to eq(3)
      expect(UserLink.links_for(ou)).to eq([
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(ou),
          'type' => 'bacon',
          'state' => {}
        },
        {
          'user_id' => u.global_id,
          'record_code' => Webhook.get_record_code(ou),
          'type' => 'org_unit_supervisor',
          'state' => {
            'user_name' => 'jobs',
            'edit_permission' => true
          }
        },
        {
          'user_id' => u2.global_id,
          'record_code' => Webhook.get_record_code(ou),
          'type' => 'org_unit_communicator',
          'state' => {
            'user_name' => 'blech'
          }
        }
      ])
    end
  end
end
