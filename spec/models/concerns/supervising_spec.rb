require 'spec_helper'

describe Supervising, :type => :model do
  describe "linking" do
    it "should grant permissions to supervisors" do
      u = User.create
      u2 = User.create
      expect(u.permissions_for(u2)).to eq({
        'user_id' => u2.global_id,
        'view_existence' => true
      })
      u.settings['supervisors'] = [{'user_id' => u2.global_id}]
      u.updated_at = Time.now
      expect(u.permissions_for(u2)).to eq({
        'user_id' => u2.global_id,
        'view_existence' => true,
        'view_detailed' => true,
        'view_deleted_boards' => true,
        'view_word_map' => true,
        'supervise' => true
      })
      u.settings['supervisors'] = [{'user_id' => u2.global_id, 'edit_permission' => true}]
      u.updated_at = Time.now
      expect(u.permissions_for(u2)).to eq({
        'user_id' => u2.global_id,
        'manage_supervision' => true,
        'view_existence' => true,
        'view_detailed' => true,
        'view_deleted_boards' => true,
        'view_word_map' => true,
        'supervise' => true,
        'edit' => true
      })
    end
    
    it "should generate a link code for the user" do
      u = User.create
      code = u.generate_link_code
      expect(code).not_to eq(nil)
      id, nonce, ts = code.split(/-/, 3)
      expect(u.settings['link_codes']).to eq([code])
      expect(Time.at(ts.to_i)).to be > 10.seconds.ago
      expect(id).to eq(u.global_id)
    end
    
    it "should flush old link codes when generating a new link code" do
      u = User.create
      good_code = "#{u.global_id}-def-#{Time.now.to_i}"
      u.settings['link_codes'] = ["#{u.global_id}-abc-1389652558", good_code]
      code = u.generate_link_code
      expect(code).not_to eq(nil)
      expect(u.settings['link_codes'].length).to eq(2)
      expect(u.settings['link_codes']).to eq([good_code, code])
    end
    
    it "should not generate a link code for a non-premium user" do
      u = User.create('expires_at' => 12.months.ago)
      expect(u.generate_link_code).to eq(nil)
      expect(u.settings['link_codes']).to eq(nil)
    end
    
    it "should link a user to a new supervisor" do
      u = User.create
      code = u.generate_link_code
      u2 = User.create
      u2.link_to_supervisee_by_code(code)
      expect(u2.settings['supervisees']).to eq([{'user_id' => u.global_id, 'user_name' => u.user_name, 'edit_permission' => true}])
      u.reload
      expect(u.settings['supervisors']).to eq([{'user_id' => u2.global_id, 'user_name' => u2.user_name, 'edit_permission' => true, 'organization_unit_ids' => []}])
    end
    
    it "should link to a supervisee by code when editing" do
      u = User.create
      code = u.generate_link_code
      expect(code).not_to eq(nil)
      u2 = User.create
      u2.process({:supervisee_code => code})
      expect(u2.settings['supervisees']).to eq([{'user_id' => u.global_id, 'user_name' => u.user_name, 'edit_permission' => true}])
      u.reload
      expect(u.settings['supervisors']).to eq([{'user_id' => u2.global_id, 'user_name' => u2.user_name, 'edit_permission' => true, 'organization_unit_ids' => []}])
    end
    
    it "should error on supervisee failure when editing" do
      res = User.process_new({:supervisee_code => "1_1"})
      expect(res.errored?).to eq(true)
      expect(res.processing_errors).to eq(["can't modify supervisees on create"])
      
      u = User.create
      code = u.generate_link_code
      expect(code).not_to eq(nil)
      u.expires_at = 12.months.ago
      u.save
      res = User.create
      res.process({:supervisee_code => code})
      expect(res.errored?).to eq(true)
      expect(res.processing_errors).to eq(["supervisee add failed"])
    end
    
    it "should remove the link code once it has been used" do
      u = User.create
      code = u.generate_link_code
      u2 = User.create
      expect(u.settings['link_codes'].length).to eq(1)
      expect(u2.link_to_supervisee_by_code(code)).to eq(true)
      expect(u.reload.settings['link_codes'].length).to eq(0)
    end
    
    it "should not create multiple links to the same supervisor" do
      u = User.create
      u2 = User.create
      u.settings['supervisors'] = [{'user_id' => u2.global_id}]
      u.save

      code = u.generate_link_code
      expect(u2.link_to_supervisee_by_code(code)).to eq(true)
      u.reload
      expect(u.settings['supervisors']).to eq([{'user_id' => u2.global_id, 'user_name' => u2.user_name, 'edit_permission' => true, 'organization_unit_ids' => []}])
    end
    
    it "should not allow a user to supervise themself" do
      u = User.create

      code = u.generate_link_code
      expect(u.link_to_supervisee_by_code(code)).to eq(false)
    end

    it "should not accept an expired link code" do
      u = User.create
      u2 = User.create

      code = "#{u.global_id}-abc-1379652558"
      u.settings['link_codes'] = [code]
      u.save
      
      expect(u2.link_to_supervisee_by_code(code)).to eq(false)
      expect(u2.settings['supervisees']).to eq(nil)
      u.reload
      expect(u.settings['supervisors']).to eq(nil)
    end
    
    it "should not link a non-premium supervisor to a user with too many non-premium supervisors" do
      u = User.create
      u.settings['supervisors'] = []
      supers = []
      5.times do |i|
        s = User.create(:expires_at => 12.months.ago)
        u.settings['supervisors'] << {'user_id' => s.global_id}
        supers << s
      end
      u.save
      u2 = User.create
      code = u.generate_link_code
      expect(u2.link_to_supervisee_by_code(code)).to eq(false)
      
      s = supers.last
      s.expires_at = 12.hours.from_now
      s.save
      expect(u2.link_to_supervisee_by_code(code)).to eq(true)
    end
    
    it "should not link a supervisor to a non-premium user" do
      u = User.create
      code = u.generate_link_code
      expect(code).not_to eq(nil)
      u.expires_at = 12.months.ago
      u.save
      u2 = User.create
      expect(u2.link_to_supervisee_by_code(code)).to eq(false)
    end
    
    it "should unlink a user and supervisor" do
      u = User.create
      u2 = User.create(:settings => {'supervisees' => [{'user_id' => u.global_id}]})
      u.settings['supervisors'] = [{'user_id' => u2.global_id}]
      u.save
      User.unlink_supervisor_from_user(u2, u)
      expect(u2.settings['supervisees']).to eq([])
      expect(u.settings['supervisors']).to eq([])
    end
    
    it "should auto-set a supervisor as a supporter role" do
      u = User.create
      u2 = User.create
      expect(u2.settings['preferences']['role']).to eq('communicator')
      User.link_supervisor_to_user(u2, u)
      expect(u2.settings['preferences']['role']).to eq('supporter')
    end
    
    it "should not auto-set a supervisor as a supporter role if already set" do
      u = User.create
      u2 = User.create
      expect(u2.settings['preferences']['role']).to eq('communicator')
      User.link_supervisor_to_user(u2, u)
      expect(u2.settings['preferences']['role']).to eq('supporter')
      u2.settings['preferences']['role'] = 'communicator'
      u2.save
      u3 = User.create
      User.link_supervisor_to_user(u2, u3)
      expect(u2.settings['preferences']['role']).to eq('communicator')
    end
    
    it "should set the org unit id if defined" do
      u1 = User.create
      u2 = User.create
      User.link_supervisor_to_user(u1, u2, nil, true, '1_1')
      expect(u2.settings['supervisors']).to eq([{
        'user_id' => u1.global_id,
        'user_name' => u1.user_name,
        'edit_permission' => true,
        'organization_unit_ids' => ['1_1']
      }])

      User.link_supervisor_to_user(u1, u2, nil, true, '1_2')
      expect(u2.settings['supervisors']).to eq([{
        'user_id' => u1.global_id,
        'user_name' => u1.user_name,
        'edit_permission' => true,
        'organization_unit_ids' => ['1_1', '1_2']
      }])
    end

    it "should correctly handle multiple org unit ids" do
      u1 = User.create
      u2 = User.create
      User.link_supervisor_to_user(u1, u2, nil, true, '1_1')
      expect(u2.settings['supervisors']).to eq([{
        'user_id' => u1.global_id,
        'user_name' => u1.user_name,
        'edit_permission' => true,
        'organization_unit_ids' => ['1_1']
      }])

      User.link_supervisor_to_user(u1, u2, nil, true, '1_2')
      expect(u2.settings['supervisors']).to eq([{
        'user_id' => u1.global_id,
        'user_name' => u1.user_name,
        'edit_permission' => true,
        'organization_unit_ids' => ['1_1', '1_2']
      }])

      User.link_supervisor_to_user(u1, u2, nil, true, '1_2')
      expect(u2.settings['supervisors']).to eq([{
        'user_id' => u1.global_id,
        'user_name' => u1.user_name,
        'edit_permission' => true,
        'organization_unit_ids' => ['1_1', '1_2']
      }])

      User.link_supervisor_to_user(u1, u2, nil, true, '1_3')
      expect(u2.settings['supervisors']).to eq([{
        'user_id' => u1.global_id,
        'user_name' => u1.user_name,
        'edit_permission' => true,
        'organization_unit_ids' => ['1_1', '1_2', '1_3']
      }])
      
      User.unlink_supervisor_from_user(u1, u2, '1_2')
      expect(u2.settings['supervisors']).to eq([{
        'user_id' => u1.global_id,
        'user_name' => u1.user_name,
        'edit_permission' => true,
        'organization_unit_ids' => ['1_1', '1_3']
      }])

      User.unlink_supervisor_from_user(u1, u2, '1_1')
      expect(u2.settings['supervisors']).to eq([{
        'user_id' => u1.global_id,
        'user_name' => u1.user_name,
        'edit_permission' => true,
        'organization_unit_ids' => ['1_3']
      }])

      User.unlink_supervisor_from_user(u1, u2, '1_3')
      expect(u2.settings['supervisors']).to eq([])
    end
  end

  describe "adding and removing" do
    it "should allow adding a supervisor by key when editing" do
      u = User.create
      u2 = User.create
      u2.process({'supervisor_key' => "add-#{u.global_id}"})
      expect(u2.reload.settings['supervisors']).to eq([{'user_id' => u.global_id, 'user_name' => u.user_name, 'edit_permission' => false, 'organization_unit_ids' => []}])
      expect(u.reload.settings['supervisees']).to eq([{'user_id' => u2.global_id, 'user_name' => u2.user_name, 'edit_permission' => false}])
    end

    it "should allow adding an edit supervisor by key when editing" do
      u = User.create
      u2 = User.create
      u2.process({'supervisor_key' => "add_edit-#{u.global_id}"})
      expect(u2.reload.settings['supervisors']).to eq([{'user_id' => u.global_id, 'user_name' => u.user_name, 'edit_permission' => true, 'organization_unit_ids' => []}])
      expect(u.reload.settings['supervisees']).to eq([{'user_id' => u2.global_id, 'user_name' => u2.user_name, 'edit_permission' => true}])
    end

    it "should raise an error when supervisor adding fails" do
      res = User.process_new({'supervisor_key' => "add-bacon"})
      expect(res.errored?).to eql(true)
    end
    
    it "should allow removing a supervisor by key when editing" do
      u = User.create
      u2 = User.create
      User.link_supervisor_to_user(u2, u)
      expect(u.reload.settings['supervisors']).to eq([{'user_id' => u2.global_id, 'user_name' => u2.user_name, 'edit_permission' => true, 'organization_unit_ids' => []}])
      expect(u2.reload.settings['supervisees']).to eq([{'user_id' => u.global_id, 'user_name' => u.user_name, 'edit_permission' => true}])
      u.process({'supervisor_key' => "remove_supervisor-#{u2.global_id}"})
      expect(u.reload.settings['supervisors']).to eq([])
      expect(u2.reload.settings['supervisees']).to eq([])
    end
    it "should raise an error when supervisor remove fails" do
      u = User.create
      u.process({'supervisor_key' => "remove_supervisor-0_1"})
      expect(u.errored?).to eql(true)
    end
    
    it "should allow removing a supervisee by key when editing" do
      u = User.create
      u2 = User.create
      User.link_supervisor_to_user(u2, u)
      expect(u.reload.settings['supervisors']).to eq([{'user_id' => u2.global_id, 'user_name' => u2.user_name, 'edit_permission' => true, 'organization_unit_ids' => []}])
      expect(u2.reload.settings['supervisees']).to eq([{'user_id' => u.global_id, 'user_name' => u.user_name, 'edit_permission' => true}])
      u2.process({'supervisor_key' => "remove_supervisee-#{u.global_id}"})
      expect(u.reload.settings['supervisors']).to eq([])
      expect(u2.reload.settings['supervisees']).to eq([])
    end
    
    it "should raise an error when supervisee remove fails" do
      u = User.create
      u.process({'supervisor_key' => "remove_supervisee-0_1"})
      expect(u.errored?).to eql(true)
    end
    
    it "should allow approving a pending org" do
      u = User.create
      o = Organization.create(:settings => {'total_licenses' => 1})
      expect(o.reload.managed_user?(u)).to eq(false)
      o.add_user(u.user_name, true)
      expect(o.reload.managed_user?(u)).to eq(false)
      u.reload.process({'supervisor_key' => "approve-org"})
      expect(o.reload.managed_user?(u)).to eq(true)
    end
    
    it "should allow approving a pending superivision org" do
      u = User.create
      o = Organization.create(:settings => {'total_licenses' => 1})
      expect(o.reload.managed_user?(u)).to eq(false)
      o.add_supervisor(u.user_name, true)
      expect(o.reload.pending_supervisor?(u.reload)).to eq(true)
      expect(o.reload.supervisor?(u)).to eq(true)
      u.reload.process({'supervisor_key' => "approve_supervision-#{o.global_id}"})
      expect(o.reload.pending_supervisor?(u)).to eq(false)
      expect(o.reload.supervisor?(u)).to eq(true)
    end
    
    it "should not error when re-approving an already-approved pending supervision org" do
      u = User.create
      o = Organization.create(:settings => {'total_licenses' => 1})
      expect(o.reload.managed_user?(u)).to eq(false)
      o.add_supervisor(u.user_name, true)
      expect(o.reload.pending_supervisor?(u.reload)).to eq(true)
      expect(o.reload.supervisor?(u)).to eq(true)
      u.reload.process({'supervisor_key' => "approve_supervision-#{o.global_id}"})
      expect(o.reload.pending_supervisor?(u)).to eq(false)
      expect(o.reload.supervisor?(u)).to eq(true)
      
      expect(u.process_supervisor_key("approve_supervision-#{o.global_id}")).to eq(true)
    end
    
    it "should allow rejecting a pending supervision org" do
      u = User.create
      o = Organization.create(:settings => {'total_licenses' => 1})
      expect(o.reload.managed_user?(u)).to eq(false)
      o.add_supervisor(u.user_name, true)
      expect(o.reload.pending_supervisor?(u.reload)).to eq(true)
      expect(o.reload.supervisor?(u)).to eq(true)
      u.reload.process({'supervisor_key' => "approve_supervision-#{o.global_id}"})
      expect(o.reload.pending_supervisor?(u)).to eq(false)
      expect(o.reload.supervisor?(u)).to eq(true)
      
      expect(u.process_supervisor_key("remove_supervision-#{o.global_id}")).to eq(true)
      expect(o.reload.pending_supervisor?(u)).to eq(false)
      expect(o.reload.supervisor?(u)).to eq(false)
    end
    
    it "should set a user to not-pending if they approve a pending org" do
      u = User.create
      o = Organization.create(:settings => {'total_licenses' => 1})
      expect(o.reload.managed_user?(u)).to eq(false)
      o.add_user(u.user_name, true)
      expect(o.reload.managed_user?(u)).to eq(false)
      u.reload.process({'supervisor_key' => "approve-org"})
      expect(o.reload.managed_user?(u)).to eq(true)
      expect(u.settings['pending']).to eq(false)
    end
    
    it "should allow rejecting a pending org" do
      u = User.create
      o = Organization.create(:settings => {'total_licenses' => 1})
      expect(o.reload.managed_user?(u)).to eq(false)
      o.add_user(u.user_name, true)
      expect(o.reload.managed_user?(u)).to eq(false)
      u.reload.process({'supervisor_key' => "remove_supervisor-org"})
      expect(o.reload.managed_user?(u)).to eq(false)
      expect(u.reload.managing_organization).to eq(nil)
    end
    
    it "should update a user's subscription if they're on a free trial and get added as a supervisor" do
      u = User.create
      u2 = User.create
      User.link_supervisor_to_user(u, u2)
      expect(u.reload.settings['subscription']['plan_id']).to eq('slp_monthly_free')
      expect(u.settings['subscription']['subscription_id']).to eq('free_auto_adjusted')
      expect(u.grace_period?).to eq(false)
    end
    
    it "should unsubscribe an auto-subscribed user if they were on a free trial, got added as a supervisor, and then removed" do
      u = User.create
      exp = u.expires_at.to_i
      u2 = User.create
      User.link_supervisor_to_user(u, u2)
      expect(u.reload.settings['subscription']['plan_id']).to eq('slp_monthly_free')
      expect(u.settings['subscription']['subscription_id']).to eq('free_auto_adjusted')
      expect(u.settings['subscription']['seconds_left']).to be > 2.weeks.to_i
      expect(u.grace_period?).to eq(false)

      User.unlink_supervisor_from_user(u, u2)
      expect(u.reload.settings['subscription']['plan_id']).to eq(nil)
      expect(u.settings['subscription']['subscription_id']).to eq(nil)
      expect(u.settings['subscription']['seconds_left']).to eq(nil)
      expect(u.expires_at.to_i).to eq(exp)
      expect(u.grace_period?).to eq(true)
    end
    
    it "should remove all supervisors when a user subscribes to a free supporter plan" do
      u = User.create
      u2 = User.create
      u3 = User.create
      User.link_supervisor_to_user(u3, u)
      u.reload
      User.link_supervisor_to_user(u, u2)
      u.reload
      expect(u.reload.settings['subscription']['plan_id']).to eq('slp_monthly_free')
      expect(u.settings['subscription']['subscription_id']).to eq('free_auto_adjusted')
      expect(u.grace_period?).to eq(false)
      expect(u.supervisors).to eq([u3])
      Worker.process_queues
      expect(u.reload.supervisors).to eq([])
    end
  end
  
  describe "managed_users" do
    it "should not grant permissions for the manager of a pending org invite" do
      u = User.create
      u2 = User.create
      o = Organization.create(:settings => {'total_licenses' => 1})
      o.add_manager(u.user_name, true)
      o.add_user(u2.user_name, true)
      
      u2.reload
      u.reload
      expect(u2.permissions_for(u)).not_to be_include('manage_supervision')
    end
    
    it "should grant manage_supervision permission for the manager of a managing org" do
      u = User.create
      u2 = User.create
      o = Organization.create(:settings => {'total_licenses' => 1})
      o.add_manager(u.user_name, true)
      o.add_user(u2.user_name, false)
      
      u2.reload
      u.reload
      expect(u2.permissions_for(u)).to be_include('manage_supervision')
    end
    
    it "should not grand manage_supervision permission for the assistant of a managing org" do
      u = User.create
      u2 = User.create
      o = Organization.create(:settings => {'total_licenses' => 1})
      o.add_manager(u.user_name, false)
      o.add_user(u2.user_name, false)
      
      u2.reload
      u.reload
      expect(u2.permissions_for(u)).not_to be_include('manage_supervision')
    end
  end
  
  describe "organization_hash" do
    it "should include new-fashioned managing org" do
      o = Organization.create(:settings => {'total_licenses' => 1})
      u = User.create
      o.add_user(u.user_name, false, true)
      
      res = u.reload.organization_hash
      expect(res.length).to eq(1)
      expect(res[0]['id']).to eq(o.global_id)
      expect(res[0]['name']).to eq(o.settings['name'])
      expect(res[0]['type']).to eq('user')
      added = Time.parse(res[0]['added'])
      expect(added).to be > (Time.now - 10)
      expect(added).to be < (Time.now + 10)
      expect(res[0]['pending']).to eq(false)
      expect(res[0]['sponsored']).to eq(true)
    end
    
    it "should include all new-fashioned managed orgs" do
      o = Organization.create
      o2 = Organization.create
      u = User.create
      o.add_manager(u.user_name, true)
      
      res = u.reload.organization_hash
      expect(res.length).to eq(1)
      expect(res[0]['id']).to eq(o.global_id)
      expect(res[0]['name']).to eq(o.settings['name'])
      expect(res[0]['type']).to eq('manager')
      added = Time.parse(res[0]['added'])
      expect(added).to be > (Time.now - 10)
      expect(added).to be < (Time.now + 10)
      expect(res[0]['full_manager']).to eq(true)
      
      o2.add_manager(u.user_name, false)
      res = u.reload.organization_hash
      expect(res.length).to eq(2)
      expect(res[1]['id']).to eq(o2.global_id)
      expect(res[1]['name']).to eq(o2.settings['name'])
      expect(res[1]['type']).to eq('manager')
      added = Time.parse(res[1]['added'])
      expect(added).to be > (Time.now - 10)
      expect(added).to be < (Time.now + 10)
      expect(res[1]['full_manager']).to eq(false)
    end
    
    it "should include all supervision orgs" do
      o = Organization.create
      o2 = Organization.create
      u = User.create
      
      o.add_supervisor(u.user_name, true)
      res = u.reload.organization_hash
      expect(res.length).to eq(1)
      expect(res[0]['id']).to eq(o.global_id)
      expect(res[0]['name']).to eq(o.settings['name'])
      expect(res[0]['type']).to eq('supervisor')
      added = Time.parse(res[0]['added'])
      expect(added).to be > (Time.now - 10)
      expect(added).to be < (Time.now + 10)
      expect(res[0]['pending']).to eq(true)
      
      o2.add_supervisor(u.user_name, false)
      res = u.reload.organization_hash
      expect(res.length).to eq(2)
      expect(res[1]['id']).to eq(o2.global_id)
      expect(res[1]['name']).to eq(o2.settings['name'])
      expect(res[1]['type']).to eq('supervisor')
      added = Time.parse(res[1]['added'])
      expect(added).to be > (Time.now - 10)
      expect(added).to be < (Time.now + 10)
      expect(res[1]['pending']).to eq(false)
    end
    
    it "should not repeat org associations" do
      o = Organization.create(:settings => {'total_licenses' => 1})
      u = User.create
      o.add_user(u.user_name, false, true)

      res = u.reload.organization_hash
      expect(res.length).to eq(1)
      expect(res[0]['id']).to eq(o.global_id)
      expect(res[0]['name']).to eq(o.settings['name'])
      expect(res[0]['type']).to eq('user')
      added = Time.parse(res[0]['added'])
      expect(added).to be > (Time.now - 10)
      expect(added).to be < (Time.now + 10)
      expect(res[0]['pending']).to eq(false)
      expect(res[0]['sponsored']).to eq(true)
    end
  end
end
