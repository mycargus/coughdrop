require 'spec_helper'

describe Relinking, :type => :model do
  describe "links_to?" do
    it "should check whether any of the buttons link to the specified board" do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.new(:settings => {})
      b2.settings['buttons'] = [
        {}, {}, {'load_board' => {}}
      ]
      b3 = Board.create(:user => u)
      
      expect(b2.links_to?(b)).to eq(false)
      expect(b2.links_to?(b3)).to eq(false)
      
      b2.settings['buttons'] << {'load_board' => {'id' => b.global_id}}
      expect(b2.links_to?(b)).to eq(true)
      expect(b2.links_to?(b3)).to eq(false)
    end
  end
  
  describe "just_for_user?" do
    it "should return true only for private boards with the author as the user" do
      u1 = User.create
      u2 = User.create
      b = Board.new(:user => u1)
      expect(b.just_for_user?(u1)).to eq(true)
      expect(b.just_for_user?(u2)).to eq(false)
      b.public = true
      expect(b.just_for_user?(u1.reload)).to eq(false)
      expect(b.just_for_user?(u2.reload)).to eq(false)
      b.public = false
      b.save
      b.share_with(u2)
      expect(b.just_for_user?(u1.reload)).to eq(false)
      expect(b.just_for_user?(u2.reload)).to eq(false)
    end
  end
  
  describe "copy_for" do
    it "should fail gracefully if no user provided" do
      u = User.create
      b = Board.create(:user => u)
      expect(b.copy_for(nil)).to eq(nil)
    end
    it "should create a new copy of the specified board for the user" do
      u = User.create
      b = Board.create(:user => u, :settings => {'hat' => true, 'image_url' => 'bob'})
      res = b.copy_for(u)
      expect(res.settings['name']).to eq(b.settings['name'])
      expect(res.settings['description']).to eq(b.settings['description'])
      expect(res.settings['image_url']).to eq(b.settings['image_url'])
      expect(res.settings['image_url']).to eq('bob')
      expect(res.settings['buttons']).to eq(b.settings['buttons'])
      expect(res.settings['license']).to eq(b.settings['license'])
      expect(res.settings['grid']).to eq(b.settings['grid'])
      expect(res.settings['hat']).to eq(nil)
      expect(res.key).to eq(b.key + "_1")
    end
    
    it "should trigger a call to map_images" do
      u = User.create
      b = Board.create(:user => u, :settings => {'hat' => true, 'image_url' => 'bob', 'buttons' => []})
      res = b.copy_for(u)
      expect(res.instance_variable_get('@images_mapped_at')).not_to eq(nil)
      expect(res.instance_variable_get('@images_mapped_at')).to be > Time.now.to_i - 5
    end
    
    it "should make public if specified" do
      u = User.create
      b = Board.create(:user => u, :settings => {'hat' => true, 'image_url' => 'bob', 'buttons' => []})
      res = b.copy_for(u, true)
      expect(res.public).to eq(true)
    end
    
    it "should update self-referential links" do
      u = User.create
      b = Board.create(:user => u)
      b.process({'buttons' => [{'id' => '1', 'load_board' => {'id' => b.global_id, 'key' => b.key}}]}, {'user' => u})
      expect(b.settings['buttons'][0]['load_board']['id']).to eq(b.global_id)
      res = b.copy_for(u, true)
      expect(res.settings['buttons'][0]['load_board']['id']).to eq(res.global_id)
    end
    
    it "should not keep updating parent links if re-added" do
      u = User.create
      b = Board.create(:user => u)
      b.process({'buttons' => [{'id' => '1', 'load_board' => {'id' => b.global_id, 'key' => b.key}}]}, {'user' => u})
      expect(b.settings['buttons'][0]['load_board']['id']).to eq(b.global_id)
      res = b.copy_for(u, true)
      expect(res.settings['buttons'][0]['load_board']['id']).to eq(res.global_id)
      b.process({'buttons' => [{'id' => '1', 'load_board' => {'id' => b.global_id, 'key' => b.key}}]}, {'user' => u})
      expect(b.settings['buttons'][0]['load_board']['id']).to eq(b.global_id)
    end
  end
  
  describe "replace_links!" do
    it "should replace links in buttons section" do
      u = User.create
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b3 = Board.create(:user => u)
      b3.settings['buttons'] = [
        {},
        {'id' => 2},
        {'load_board' => {'id' => b1.global_id}},
        {'load_board' => {'id' => b3.global_id}}
      ]
      b3.replace_links!(b1, b2)
      expect(b3.settings['buttons']).to eq([
        {},
        {'id' => 2},
        {'load_board' => {'id' => b2.global_id, 'key' => b2.key}},
        {'load_board' => {'id' => b3.global_id}}
      ])
    end
  end
  
  describe "copy_board_links_for" do
    it "should copy downstream boards" do
      u1 = User.create
      u2 = User.create
      b1 = Board.create(:user => u1, :public => true)
      b1a = Board.create(:user => u1, :public => true)
      b1.settings['buttons'] = [{'id' => 1, 'load_board' => {'key' => b1a.key, 'id' => b1a.global_id}}]
      b1.save!
      b1.track_downstream_boards!
      expect(b1.settings['downstream_board_ids']).to eq([b1a.global_id])
      b2 = b1.copy_for(u2)
      expect(Board).to receive(:relink_board_for) do |user, opts|
        boards = opts[:boards]
        pending_replacements = opts[:pending_replacements]
        action = opts[:update_preference]
        expect(user).to eq(u2)
        expect(boards.length).to eq(2)
        expect(boards).to eq([b1, b1a])
        expect(pending_replacements.length).to eq(2)
        expect(pending_replacements[0]).to eq([b1, b2])
        expect(pending_replacements[1][0]).to eq(b1a)
        expect(action).to eq('update_inline')
      end
      Board.copy_board_links_for(u2, {:starting_old_board => b1, :starting_new_board => b2})
    end
    
    it "should not create duplicate copies" do
      u1 = User.create
      u2 = User.create
      b1 = Board.create(:user => u1, :public => true)
      b1a = Board.create(:user => u1, :public => true)
      b1b = Board.create(:user => u1, :public => true)
      b1.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'key' => b1a.key, 'id' => b1a.global_id}},
        {'id' => 2, 'load_board' => {'key' => b1b.key, 'id' => b1b.global_id}}
      ]
      b1.instance_variable_set('@buttons_changed', true);
      b1.save!
      b1a.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'key' => b1b.key, 'id' => b1b.global_id}},
        {'id' => 2, 'load_board' => {'key' => b1b.key, 'id' => b1b.global_id}}
      ]
      b1a.instance_variable_set('@buttons_changed', true);
      b1a.save!
      
      Worker.process_queues
      expect(b1.reload.settings['downstream_board_ids']).to eq([b1a.global_id, b1b.global_id])
      expect(b1a.reload.settings['downstream_board_ids']).to eq([b1b.global_id])
      
      expect(Board.count).to eq(3)
      
      b2 = b1.copy_for(u2)
      Board.copy_board_links_for(u2, {:starting_old_board => b1, :starting_new_board => b2})
      ids = Board.all.map(&:global_id).sort

      Worker.process_queues

      expect(b2.reload.settings['downstream_board_ids']).to eq([ids[-2], ids[-1]])
      expect(Board.count).to eq(6)
    end
    
    it "should not copy downstream boards that it doesn't have permission to access" do
      u1 = User.create
      u2 = User.create
      b1 = Board.create(:user => u1, :public => true)
      b1a = Board.create(:user => u1)
      b1.settings['buttons'] = [{'id' => 1, 'load_board' => {'key' => b1a.key, 'id' => b1a.global_id}}]
      b1.save!
      b1.track_downstream_boards!
      expect(b1.settings['downstream_board_ids']).to eq([b1a.global_id])
      b2 = b1.copy_for(u2)
      expect(Board).to receive(:relink_board_for) do |user, opts|
        boards = opts[:boards]
        pending_replacements = opts[:pending_replacements]
        action = opts[:update_preference]
        expect(user).to eq(u2)
        expect(boards.length).to eq(2)
        expect(boards).to eq([b1, b1a])
        expect(pending_replacements.length).to eq(1)
        expect(pending_replacements[0]).to eq([b1, b2])
        expect(action).to eq('update_inline')
      end
      Board.copy_board_links_for(u2, {:starting_old_board => b1, :starting_new_board => b2})
    end
    
    it "should update links in the root board and all downstream boards" do
      u1 = User.create
      u2 = User.create
      b1 = Board.create(:user => u1, :public => true)
      b1a = Board.create(:user => u1, :public => true)
      b1b = Board.create(:user => u1, :public => true)
      b1a.settings['buttons'] = [{'id' => 1, 'load_board' => {'key' => b1b.key, 'id' => b1b.global_id, 'link_disabled' => true}}]
      b1a.save!
      b1a.track_downstream_boards!
      b1.settings['buttons'] = [{'id' => 1, 'load_board' => {'key' => b1a.key, 'id' => b1a.global_id}}]
      b1.save!
      b1.track_downstream_boards!
      expect(b1.settings['downstream_board_ids']).to eq([b1a.global_id, b1b.global_id])
      b2 = b1.copy_for(u2)
      Board.copy_board_links_for(u2, {:starting_old_board => b1, :starting_new_board => b2})

      b2.reload
      expect(b2.settings['buttons'][0]['load_board']['key']).not_to eq(b1a.key)
      b2a = Board.find_by_path(b2.settings['buttons'][0]['load_board']['key'])
      expect(b2a.settings['buttons'][0]['load_board']['key']).not_to eq(b1b.key)
      expect(b2a.public).to eq(false)
      b2b = Board.find_by_path(b2a.settings['buttons'][0]['load_board']['key'])
      expect(b2.settings['buttons'][0]['load_board']).to eq({'key' => b2a.key, 'id' => b2a.global_id})
      expect(b2a.settings['buttons'][0]['load_board']).to eq({'key' => b2b.key, 'id' => b2b.global_id, 'link_disabled' => true})
      expect(b2b.public).to eq(false)
    end
    
    it "should only copy explicitly-listed boards if there's a list" do
      u1 = User.create
      u2 = User.create
      b1 = Board.create(:user => u1, :public => true)
      b1a = Board.create(:user => u1, :public => true)
      b1b = Board.create(:user => u1, :public => true)
      b1a.settings['buttons'] = [{'id' => 1, 'load_board' => {'key' => b1b.key, 'id' => b1b.global_id, 'link_disabled' => true}}]
      b1a.save!
      b1a.track_downstream_boards!
      b1.settings['buttons'] = [{'id' => 1, 'load_board' => {'key' => b1a.key, 'id' => b1a.global_id}}]
      b1.save!
      b1.track_downstream_boards!
      expect(b1.settings['downstream_board_ids']).to eq([b1a.global_id, b1b.global_id])
      b2 = b1.copy_for(u2)
      Board.copy_board_links_for(u2, {:valid_ids => [b1.global_id, b1a.global_id], :starting_old_board => b1, :starting_new_board => b2})

      b2.reload
      expect(b2.settings['buttons'][0]['load_board']['key']).not_to eq(b1a.key)
      b2a = Board.find_by_path(b2.settings['buttons'][0]['load_board']['key'])
      expect(b2a.settings['buttons'][0]['load_board']['key']).to eq(b1b.key)
    end
    
    it "should not copy explicitly-listed boards unless there's a valid route to the board that makes it happen" do
      u1 = User.create
      u2 = User.create
      b1 = Board.create(:user => u1, :public => true)
      b1a = Board.create(:user => u1, :public => true)
      b1b = Board.create(:user => u1, :public => true)
      b1a.settings['buttons'] = [{'id' => 1, 'load_board' => {'key' => b1b.key, 'id' => b1b.global_id, 'link_disabled' => true}}]
      b1a.save!
      b1a.track_downstream_boards!
      b1.settings['buttons'] = [{'id' => 1, 'load_board' => {'key' => b1a.key, 'id' => b1a.global_id}}]
      b1.save!
      b1.track_downstream_boards!
      expect(b1.settings['downstream_board_ids']).to eq([b1a.global_id, b1b.global_id])
      b2 = b1.copy_for(u2)
      Board.copy_board_links_for(u2, {:valid_ids => [b1.global_id, b1b.global_id], :starting_old_board => b1, :starting_new_board => b2})

      b2.reload
      expect(b2.settings['buttons'][0]['load_board']['key']).to eq(b1a.key)
      b2a = Board.find_by_path(b2.settings['buttons'][0]['load_board']['key'])
      expect(b2a.settings['buttons'][0]['load_board']['key']).to eq(b1b.key)
      b2b = Board.find_by_path(b2a.settings['buttons'][0]['load_board']['key'])
    end    

    it "should copy downstream boards when supervisor is copying with permission" do
      u1 = User.create
      u2 = User.create
      u3 = User.create
      b1 = Board.create(:user => u1)
      b1a = Board.create(:user => u1)
      User.link_supervisor_to_user(u2, u1, nil, true)
      b1.settings['buttons'] = [{'id' => 1, 'load_board' => {'key' => b1a.key, 'id' => b1a.global_id}}]
      b1.save!
      b1.track_downstream_boards!
      expect(b1.settings['downstream_board_ids']).to eq([b1a.global_id])
      b2 = b1.copy_for(u3)
      expect(Board).to receive(:relink_board_for) do |user, opts|
        boards = opts[:boards]
        pending_replacements = opts[:pending_replacements]
        action = opts[:update_preference]
        expect(opts[:authorized_user]).to eq(u2)
        expect(user).to eq(u3)
        expect(boards.length).to eq(2)
        expect(boards).to eq([b1, b1a])
        expect(pending_replacements.length).to eq(2)
        expect(pending_replacements[0]).to eq([b1, b2])
        expect(pending_replacements[1][0]).to eq(b1a)
        expect(action).to eq('update_inline')
      end
      Board.copy_board_links_for(u3, {:starting_old_board => b1, :starting_new_board => b2, :authorized_user => u2})
    end
    
    it "should make public if specified" do
      u1 = User.create
      u2 = User.create
      b1 = Board.create(:user => u1, :public => true)
      b1a = Board.create(:user => u1, :public => true)
      b1.settings['buttons'] = [{'id' => 1, 'load_board' => {'key' => b1a.key, 'id' => b1a.global_id}}]
      b1.save!
      b1.track_downstream_boards!
      expect(b1.settings['downstream_board_ids']).to eq([b1a.global_id])
      b2 = b1.copy_for(u2)
      expect(Board).to receive(:relink_board_for) do |user, opts|
        boards = opts[:boards]
        pending_replacements = opts[:pending_replacements]
        action = opts[:update_preference]
        expect(user).to eq(u2)
        expect(boards.length).to eq(2)
        expect(boards).to eq([b1, b1a])
        expect(pending_replacements.length).to eq(2)
        expect(pending_replacements[0]).to eq([b1, b2])
        expect(pending_replacements[1][0]).to eq(b1a)
        expect(action).to eq('update_inline')
      end
      Board.copy_board_links_for(u2, {:starting_old_board => b1, :starting_new_board => b2, :make_public => true})
      Worker.process_queues
      expect(b2.reload.settings['downstream_board_ids'].length).to eq(1)
      boards = Board.find_all_by_global_id(b2.settings['downstream_board_ids'])
      expect(boards.map(&:public)).to eq([true])
    end
    
    it "should mark everything with the correct copy_id" do
      u1 = User.create
      u2 = User.create
      b1 = Board.create(:user => u1, :public => true)
      b1a = Board.create(:user => u1, :public => true)
      b1b = Board.create(:user => u1, :public => true)
      b1a.settings['buttons'] = [{'id' => 1, 'load_board' => {'key' => b1b.key, 'id' => b1b.global_id, 'link_disabled' => true}}]
      b1a.save!
      b1a.track_downstream_boards!
      b1.settings['buttons'] = [{'id' => 1, 'load_board' => {'key' => b1a.key, 'id' => b1a.global_id}}]
      b1.save!
      b1.track_downstream_boards!
      expect(b1.settings['downstream_board_ids']).to eq([b1a.global_id, b1b.global_id])
      b2 = b1.copy_for(u2)
      Board.copy_board_links_for(u2, {:valid_ids => [b1.global_id, b1a.global_id], :starting_old_board => b1, :starting_new_board => b2})

      b2.reload
      expect(b2.settings['buttons'][0]['load_board']['key']).not_to eq(b1a.key)
      expect(b2.settings['copy_id']).to eq(nil)
      b2a = Board.find_by_path(b2.settings['buttons'][0]['load_board']['key'])
      expect(b2a.settings['buttons'][0]['load_board']['key']).to eq(b1b.key)
      expect(b2a.settings['copy_id']).to eq(b2.global_id)
    end
  end
 
  describe "replace_board_for" do
    it "should copy only boards that are changed and that need copying as opposed to updating" do
      u = User.create
      old = Board.create(:user => u, :public => true, :settings => {'name' => 'old'})
      ref = Board.create(:user => u, :public => true, :settings => {'name' => 'ref'})
      leave_alone = Board.create(:user => u, :public => true, :settings => {'name' => 'leave alone'})
      change_inline = Board.create(:user => u, :settings => {'name' => 'change inline'})
      old.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => ref.global_id}},
        {'id' => 2, 'load_board' => {'id' => leave_alone.global_id}},
        {'id' => 3, 'load_board' => {'id' => change_inline.global_id}}
      ]
      old.save
      new = old.copy_for(u)
      new.settings['name'] = 'new'
      new.save
      ref.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => old.global_id}}
      ]
      ref.save
      change_inline.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => old.global_id}}
      ]
      change_inline.save
      u.settings['preferences']['home_board'] = {'id' => ref.global_id}
      u.save
      Worker.process_queues
      expect(ref.reload.settings['immediately_downstream_board_ids']).to eq([old.global_id])
      expect(ref.reload.settings['downstream_board_ids']).to eq([old.global_id, leave_alone.global_id, change_inline.global_id])
      
      Board.replace_board_for(u.reload, {:starting_old_board => old.reload, :starting_new_board => new.reload})
      expect(u.settings['preferences']['home_board']['id']).not_to eq(ref.global_id)
      b = Board.find_by_path(u.settings['preferences']['home_board']['id'])
      expect(b).not_to eq(nil)
      expect(b.settings['name']).to eq('ref')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).not_to be_include(old.global_id)
      b = Board.find_by_path(b.settings['immediately_downstream_board_ids'][0])
      expect(b).not_to eq(nil)
      expect(b.settings['name']).to eq('new')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(3)
      expect(b.settings['immediately_downstream_board_ids']).not_to be_include(ref.global_id)
      expect(b.settings['immediately_downstream_board_ids']).to be_include(leave_alone.global_id)
      expect(b.settings['immediately_downstream_board_ids']).to be_include(change_inline.global_id)
      
      b = change_inline.reload
      expect(b.settings['name']).to eq('change inline')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).to eq([new.global_id])
      
      expect(ref.reload.child_boards.count).to eq(1)
      expect(change_inline.reload.child_boards.count).to eq(0)
      expect(leave_alone.reload.child_boards.count).to eq(0)
      expect(old.reload.child_boards.count).to eq(1)
    end
    
    it "should traverse all the way upstream" do
      u = User.create
      level0 = Board.create(:user => u, :public => true, :settings => {'name' => 'level0'})
      level1 = Board.create(:user => u, :public => true, :settings => {'name' => 'level1'})
      level2 = Board.create(:user => u, :public => true, :settings => {'name' => 'level2'})
      level3 = Board.create(:user => u, :public => true, :settings => {'name' => 'level3'})
      
      level0.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => level1.global_id}}
      ]
      level0.save
      level1.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => level2.global_id}}
      ]
      level1.save
      level2.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => level3.global_id}}
      ]
      level2.save
      
      new_level3 = level3.copy_for(u)
      new_level3.settings['name'] = 'new_level3'
      new_level3.save
      u.settings['preferences']['home_board'] = {'id' => level0.global_id}
      u.save
      Worker.process_queues
      
      Board.replace_board_for(u.reload, {:starting_old_board => level3.reload, :starting_new_board => new_level3.reload})
      expect(u.settings['preferences']['home_board']['id']).not_to eq(level0.global_id)
      b = Board.find_by_path(u.settings['preferences']['home_board']['id'])
      expect(b).not_to eq(nil)
      expect(b.settings['name']).to eq('level0')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).not_to be_include(level1.global_id)
      
      b = Board.find_by_path(b.settings['immediately_downstream_board_ids'][0])
      expect(b).not_to eq(nil)
      expect(b.settings['name']).to eq('level1')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).not_to be_include(level2.global_id)
      
      b = Board.find_by_path(b.settings['immediately_downstream_board_ids'][0])
      expect(b).not_to eq(nil)
      expect(b.settings['name']).to eq('level2')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).not_to be_include(level3.global_id)
      expect(b.settings['immediately_downstream_board_ids']).to be_include(new_level3.global_id)
      
      expect(level0.reload.child_boards.count).to eq(1)
      expect(level1.reload.child_boards.count).to eq(1)
      expect(level2.reload.child_boards.count).to eq(1)
      expect(level3.reload.child_boards.count).to eq(1)
    end
    
    it "should replace the user's home board preference if changed" do
      u = User.create
      old = Board.create(:user => u, :public => true, :settings => {'name' => 'old'})
      ref = Board.create(:user => u, :public => true, :settings => {'name' => 'ref'})
      leave_alone = Board.create(:user => u, :public => true, :settings => {'name' => 'leave alone'})
      change_inline = Board.create(:user => u, :settings => {'name' => 'change inline'})
      old.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => ref.global_id}},
        {'id' => 2, 'load_board' => {'id' => leave_alone.global_id}},
        {'id' => 3, 'load_board' => {'id' => change_inline.global_id}}
      ]
      old.save
      new = old.copy_for(u)
      new.settings['name'] = 'new'
      new.save
      ref.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => old.global_id}}
      ]
      ref.save
      change_inline.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => old.global_id}}
      ]
      change_inline.save
      u.settings['preferences']['home_board'] = {'id' => ref.global_id}
      u.save
      Worker.process_queues
      expect(ref.reload.settings['immediately_downstream_board_ids']).to eq([old.global_id])
      expect(ref.reload.settings['downstream_board_ids']).to eq([old.global_id, leave_alone.global_id, change_inline.global_id])
      
      Board.replace_board_for(u.reload, {:starting_old_board => old.reload, :starting_new_board => new.reload})
      expect(u.settings['preferences']['home_board']['id']).not_to eq(ref.global_id)
    end
    
    it "should not make copies for boards that the user isn't allowed to access" do
      secret = User.create
      u = User.create
      level0 = Board.create(:user => secret, :settings => {'name' => 'level0'})
      level1 = Board.create(:user => u, :public => true, :settings => {'name' => 'level1'})
      
      level0.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => level1.global_id}}
      ]
      level0.save
      
      new_level1 = level1.copy_for(u)
      new_level1.settings['name'] = 'new_level3'
      new_level1.save
      u.settings['preferences']['home_board'] = {'id' => level0.global_id}
      u.save
      Worker.process_queues
      
      Board.replace_board_for(u.reload, {:starting_old_board => level1.reload, :starting_new_board => new_level1.reload})
      expect(u.settings['preferences']['home_board']['id']).to eq(level0.global_id)
    end
    
    it "should make copies of boards the user can edit if specified" do
      u = User.create
      u2 = User.create
      old = Board.create(:user => u, :public => true, :settings => {'name' => 'old'})
      make_copy = Board.create(:user => u, :public => true, :settings => {'name' => 'make copy'})
      make_copy2 = Board.create(:user => u2, :public => true, :settings => {'name' => 'make copy too'})
      make_copy.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => old.global_id}}
      ]
      make_copy.save
      make_copy2.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => make_copy.global_id}}
      ]
      make_copy2.save
      Worker.process_queues
      new = old.copy_for(u)
      new.settings['name'] = 'new'
      new.save
      u.settings['preferences']['home_board'] = {'id' => make_copy2.global_id}
      u.save
      Worker.process_queues
      expect(make_copy.reload.settings['immediately_downstream_board_ids']).to eq([old.global_id])
      expect(make_copy.reload.settings['downstream_board_ids']).to eq([old.global_id])
      expect(make_copy2.reload.settings['immediately_downstream_board_ids']).to eq([make_copy.global_id])
      expect(make_copy2.reload.settings['downstream_board_ids'].sort).to eq([make_copy.global_id, old.global_id].sort)
      
      Board.replace_board_for(u.reload, {:starting_old_board => old.reload, :starting_new_board => new.reload, :update_inline => false})
      expect(u.settings['preferences']['home_board']['id']).not_to eq(make_copy2.global_id)
      b = Board.find_by_path(u.settings['preferences']['home_board']['id'])
      expect(b).not_to eq(nil)
      expect(b.settings['name']).to eq('make copy too')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).not_to be_include(make_copy.global_id)
      b = Board.find_by_path(b.settings['immediately_downstream_board_ids'][0])
      expect(b).not_to eq(nil)
      expect(b.settings['name']).to eq('make copy')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).to eql([new.global_id])
      
      b = make_copy2.reload
      expect(b.settings['name']).to eq('make copy too')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).to eq([make_copy.global_id])

      b = make_copy.reload
      expect(b.settings['name']).to eq('make copy')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).to eq([old.global_id])
    end
    
    it "should not make copies of boards the user can edit if specified" do
      u = User.create
      u2 = User.create
      old = Board.create(:user => u, :public => true, :settings => {'name' => 'old'})
      make_copy = Board.create(:user => u, :public => true, :settings => {'name' => 'make copy'})
      make_copy2 = Board.create(:user => u2, :public => true, :settings => {'name' => 'make copy too'})
      make_copy.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => old.global_id}}
      ]
      make_copy.save
      make_copy2.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => make_copy.global_id}}
      ]
      make_copy2.save
      Worker.process_queues
      new = old.copy_for(u)
      new.settings['name'] = 'new'
      new.save
      u.settings['preferences']['home_board'] = {'id' => make_copy2.global_id}
      u.save
      Worker.process_queues
      expect(make_copy.reload.settings['immediately_downstream_board_ids']).to eq([old.global_id])
      expect(make_copy.reload.settings['downstream_board_ids']).to eq([old.global_id])
      expect(make_copy2.reload.settings['immediately_downstream_board_ids']).to eq([make_copy.global_id])
      expect(make_copy2.reload.settings['downstream_board_ids'].sort).to eq([make_copy.global_id, old.global_id].sort)
      
      Board.replace_board_for(u.reload, {:starting_old_board => old.reload, :starting_new_board => new.reload, :update_inline => true})
      expect(u.settings['preferences']['home_board']['id']).to eq(make_copy2.global_id)

      b = make_copy2.reload
      expect(b.settings['name']).to eq('make copy too')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).to eq([make_copy.global_id])

      b = make_copy.reload
      expect(b.settings['name']).to eq('make copy')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).to eq([new.global_id])
    end
    
    it "should only copy boards explicitly listed if there's a list" do
      u = User.create
      level0 = Board.create(:user => u, :public => true, :settings => {'name' => 'level0'})
      level1 = Board.create(:user => u, :public => true, :settings => {'name' => 'level1'})
      level2 = Board.create(:user => u, :public => true, :settings => {'name' => 'level2'})
      level2b = Board.create(:user => u, :public => true, :settings => {'name' => 'level2b'})
      level3 = Board.create(:user => u, :public => true, :settings => {'name' => 'level3'})
      
      level0.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => level1.global_id}}
      ]
      level0.save
      level1.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => level2.global_id}},
        {'id' => 2, 'load_board' => {'id' => level2b.global_id}}
      ]
      level1.save
      level2.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => level3.global_id}}
      ]
      level2.save
      
      new_level3 = level3.copy_for(u)
      new_level3.settings['name'] = 'new_level3'
      new_level3.save
      u.settings['preferences']['home_board'] = {'id' => level0.global_id}
      u.save
      Worker.process_queues
      
      Board.replace_board_for(u.reload, {:valid_ids => [level0.global_id, level1.global_id, level2.global_id, level3.global_id], :starting_old_board => level3.reload, :starting_new_board => new_level3.reload})
      expect(u.settings['preferences']['home_board']['id']).not_to eq(level0.global_id)
      b = Board.find_by_path(u.settings['preferences']['home_board']['id'])
      expect(b).not_to eq(nil)
      expect(b.settings['name']).to eq('level0')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).not_to be_include(level1.global_id)
      
      b = Board.find_by_path(b.settings['immediately_downstream_board_ids'][0])
      expect(b).not_to eq(nil)
      expect(b.settings['name']).to eq('level1')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(2)
      expect(b.settings['immediately_downstream_board_ids']).not_to be_include(level2.global_id)
      expect(b.settings['immediately_downstream_board_ids']).to be_include(level2b.global_id)
      
      b = Board.find_by_path(b.settings['immediately_downstream_board_ids'].detect{|id| id != level2b.global_id})
      expect(b).not_to eq(nil)
      expect(b.settings['name']).to eq('level2')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).not_to be_include(level3.global_id)
      expect(b.settings['immediately_downstream_board_ids']).to be_include(new_level3.global_id)
      
      expect(level0.reload.child_boards.count).to eq(1)
      expect(level1.reload.child_boards.count).to eq(1)
      expect(level2.reload.child_boards.count).to eq(1)
      expect(level3.reload.child_boards.count).to eq(1)
    end
    
    it "should not copy explicitly-listed boards if there's not a valid copyable route to the board" do
      u = User.create
      level0 = Board.create(:user => u, :public => true, :settings => {'name' => 'level0'})
      level1 = Board.create(:user => u, :public => true, :settings => {'name' => 'level1'})
      level2 = Board.create(:user => u, :public => true, :settings => {'name' => 'level2'})
      level3 = Board.create(:user => u, :public => true, :settings => {'name' => 'level3'})
      
      level0.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => level1.global_id}}
      ]
      level0.save
      level1.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => level2.global_id}}
      ]
      level1.save
      level2.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => level3.global_id}}
      ]
      level2.save
      
      new_level3 = level3.copy_for(u)
      new_level3.settings['name'] = 'new_level3'
      new_level3.save
      u.settings['preferences']['home_board'] = {'id' => level0.global_id}
      u.save
      Worker.process_queues
      
      Board.replace_board_for(u.reload, {:valid_ids => [level3.global_id, level2.global_id], :starting_old_board => level3.reload, :starting_new_board => new_level3.reload})
      expect(u.settings['preferences']['home_board']['id']).to eq(level0.global_id)
      b = Board.find_by_path(u.settings['preferences']['home_board']['id'])
      expect(b).to eq(level0)
      expect(b.settings['name']).to eq('level0')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).to be_include(level1.global_id)
      
      b = Board.find_by_path(b.settings['immediately_downstream_board_ids'][0])
      expect(b).to eq(level1)
      expect(b.settings['name']).to eq('level1')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).to be_include(level2.global_id)
      
      b = Board.find_by_path(b.settings['immediately_downstream_board_ids'][0])
      expect(b).to eq(level2)
      expect(b.settings['name']).to eq('level2')
      expect(b.settings['immediately_downstream_board_ids'].length).to eq(1)
      expect(b.settings['immediately_downstream_board_ids']).to be_include(level3.global_id)
      expect(b.settings['immediately_downstream_board_ids']).to_not be_include(new_level3.global_id)
      
      expect(level0.reload.child_boards.count).to eq(0)
      expect(level1.reload.child_boards.count).to eq(0)
      expect(level2.reload.child_boards.count).to eq(1)
      expect(level3.reload.child_boards.count).to eq(1)
    end

    it "should make public if specified" do
      u = User.create
      u2 = User.create
      old = Board.create(:user => u, :public => true, :settings => {'name' => 'old'})
      make_copy = Board.create(:user => u, :public => true, :settings => {'name' => 'make copy'})
      make_copy2 = Board.create(:user => u2, :public => true, :settings => {'name' => 'make copy too'})
      make_copy.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => old.global_id}}
      ]
      make_copy.save
      make_copy2.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => make_copy.global_id}}
      ]
      make_copy2.save
      Worker.process_queues
      new = old.copy_for(u)
      new.settings['name'] = 'new'
      new.save
      u.settings['preferences']['home_board'] = {'id' => make_copy2.global_id}
      u.save
      Worker.process_queues
      expect(make_copy.reload.settings['immediately_downstream_board_ids']).to eq([old.global_id])
      expect(make_copy.reload.settings['downstream_board_ids']).to eq([old.global_id])
      expect(make_copy2.reload.settings['immediately_downstream_board_ids']).to eq([make_copy.global_id])
      expect(make_copy2.reload.settings['downstream_board_ids'].sort).to eq([make_copy.global_id, old.global_id].sort)
      
      Board.replace_board_for(u.reload, {:starting_old_board => old.reload, :starting_new_board => new.reload, :update_inline => false, :make_public => true})
      expect(u.settings['preferences']['home_board']['id']).not_to eq(make_copy2.global_id)
      b = Board.find_by_path(u.settings['preferences']['home_board']['id'])
      expect(b).not_to eq(nil)
      expect(b.public).to eq(true)
      b = Board.find_by_path(b.settings['immediately_downstream_board_ids'][0])
      expect(b).not_to eq(nil)
      expect(b.public).to eq(true)
      
      b = make_copy2.reload
      expect(b.public).to eq(true)

      b = make_copy.reload
      expect(b.public).to eq(true)
    end
  end
  
  it "should copy upstream boards for the specified user" do
    author = User.create
    parent = User.create

    level0 = Board.create(:user => author, :public => true, :settings => {'name' => 'level0'})
    level1 = Board.create(:user => author, :public => true, :settings => {'name' => 'level1'})
    
    level0.settings['buttons'] = [
      {'id' => 1, 'load_board' => {'id' => level1.global_id}}
    ]
    level0.save
    
    new_level1 = level1.copy_for(parent)
    new_level1.settings['name'] = 'new_level3'
    new_level1.save
    parent.settings['preferences']['home_board'] = {'id' => level0.global_id}
    parent.save
    Worker.process_queues
    
    parent.reload.replace_board(level1.global_id, new_level1.global_id)
    Worker.process_queues
    
    expect(parent.settings['preferences']['home_board']['id']).not_to eq(level0.global_id)
  end
end
