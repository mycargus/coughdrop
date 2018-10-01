require 'spec_helper'

describe Board, :type => :model do
  describe "paper_trail" do
    it "should make sure paper trail is doing its thing"
  end
  
  describe "permissions" do
    it "should allow view if public or author" do
      u = User.create
      b = Board.new(:user => u)
      u2 = User.new
      expect(b.allows?(nil, 'view')).to eq(false)
      expect(b.allows?(u, 'view')).to eq(true)
      expect(b.allows?(u2, 'view')).to eq(false)
      b.public = true
      expect(b.allows?(nil, 'view')).to eq(true)
      expect(b.allows?(u, 'view')).to eq(true)
      expect(b.allows?(u2, 'view')).to eq(true)
    end
    
    it "should allow edit and delete if author" do
      u = User.create
      b = Board.new(:user => u)
      u2 = User.new
      expect(b.allows?(nil, 'edit')).to eq(false)
      expect(b.allows?(u, 'edit')).to eq(true)
      expect(b.allows?(u2, 'edit')).to eq(false)
      expect(b.allows?(nil, 'delete')).to eq(false)
      expect(b.allows?(u, 'delete')).to eq(true)
      expect(b.allows?(u2, 'delete')).to eq(false)
      b.public = true
      expect(b.allows?(nil, 'edit')).to eq(false)
      expect(b.allows?(u, 'edit')).to eq(true)
      expect(b.allows?(u2, 'edit')).to eq(false)
      expect(b.allows?(nil, 'delete')).to eq(false)
      expect(b.allows?(u, 'delete')).to eq(true)
      expect(b.allows?(u2, 'delete')).to eq(false)
    end
    
    it "should allow supervisors to edit and delete" do
      u = User.create
      u2 = User.create
      User.link_supervisor_to_user(u2, u)
      b = Board.new(:user => u.reload)
      expect(b.permissions_for(u2)).to eq({
        'user_id' => u2.global_id,
        'view' => true,
        'edit' => true,
        'delete' => true,
        'share' => true
      })
    end

    it "should allow org admins to edit and delete" do
      o = Organization.create(:settings => {'total_licenses' => 1})
      u = User.create
      m = User.create
      
      o.add_manager(m.user_name, true)
      o.add_user(u.user_name, false)
      m.reload
      u.reload
      b = Board.create(user: u)
      
      expect(b.allows?(m, 'view')).to eq(true)
      expect(b.allows?(m, 'edit')).to eq(true)
      expect(b.allows?(m, 'delete')).to eq(true)
    end

    it "should not allow global admins to edit and delete" do
      o = Organization.create(:admin => true, :settings => {'total_licenses' => 1})
      u = User.create
      m = User.create
      
      o.add_manager(m.user_name, true)
      m.reload
      b = Board.create(user: u)
      
      expect(b.allows?(m, 'view')).to eq(true)
      expect(b.allows?(m, 'edit')).to eq(false)
      expect(b.allows?(m, 'delete')).to eq(false)
    end

    it "should allow read-only supervisors to view but not edit or delete" do
      u = User.create
      u2 = User.create
      User.link_supervisor_to_user(u2, u, nil, false)
      b = Board.new(:user => u.reload)
      expect(b.permissions_for(u2)).to eq({
        'user_id' => u2.global_id,
        'view' => true
      })
    end
    
    it "should allow supervisors to view but not edit or delete if the board is created by someone else and shared privately with the communicator" do
      communicator = User.create
      supervisor = User.create
      random = User.create
      User.link_supervisor_to_user(supervisor, communicator, nil, true)
      b = Board.create(:user => random)
      b.share_with(communicator)
      expect(b.permissions_for(communicator)).to eq({
        'user_id' => communicator.global_id,
        'view' => true
      })
      expect(b.permissions_for(supervisor.reload)).to eq({
        'user_id' => supervisor.global_id,
        'view' => true
      })
    end
    
    it "should not allow recursive permissions (I shouldn't be able to see the supervisee of my supervisee" do
      communicator = User.create
      supervisor = User.create
      communicators_supervisee = User.create
      User.link_supervisor_to_user(supervisor, communicator, nil, true)
      User.link_supervisor_to_user(communicator, communicators_supervisee, nil, true)
      b = Board.create(:user => communicators_supervisee.reload)
      expect(b.permissions_for(communicator.reload)).to eq({
        'user_id' => communicator.global_id,
        'view' => true,
        'edit' => true,
        'delete' => true,
        'share' => true
      })
      expect(b.permissions_for(supervisor.reload)).to eq({
        'user_id' => supervisor.global_id
      })
    end
    
    it "should not allow a supervisee to see their supervisor's boards" do
      u = User.create
      u2 = User.create
      User.link_supervisor_to_user(u2, u, nil, false)
      b = Board.new(:user => u2.reload)
      expect(b.permissions_for(u)).to eq({
        'user_id' => u.global_id
      })      
    end
  end
  
  describe "starred_by?" do
    it "should check list and match on global_id" do
      u = User.create
      b = Board.new(:user => u, :settings => {})
      u2 = User.new
      b.settings['starred_user_ids'] = ['a', 3, 'b', u.global_id, false, nil]
      expect(b.starred_by?(u)).to eq(true)
      expect(b.starred_by?(u2)).to eq(false)
      expect(b.starred_by?(nil)).to eq(false)
    end
  end

  describe "star" do
    it "should not fail if settings aren't set yet" do
      u = User.new
      u.id = 12
      b = Board.new
      b.star(u, true)
    end
    
    it "should add the user if set to star" do
      u = User.new
      u.id = 12
      expect(u.global_id).not_to eq(nil)
      b = Board.new
      b.star(u, true)
      expect(b.settings['starred_user_ids']).to eq([u.global_id])
    end
    
    it "should not keep repeat ids" do
      u = User.new
      u.id = 12
      expect(u.global_id).not_to eq(nil)
      b = Board.new
      b.star(u, true)
      b.star(u, true)
      b.star(u, true)
      expect(b.settings['starred_user_ids']).to eq([u.global_id])
    end
    
    it "should remove the user if set to unstar" do
      u = User.new
      u.id = 12
      expect(u.global_id).not_to eq(nil)
      b = Board.new
      b.star(u, true)
      expect(b.settings['starred_user_ids']).to eq([u.global_id])
      b.star(u, false)
      expect(b.settings['starred_user_ids']).to eq([])
    end
    
    it "should schedule an update for the user record" do
      u = User.new
      u.id = 12
      expect(u.global_id).not_to eq(nil)
      b = Board.new
      b.star(u, true)
      expect(Worker.scheduled?(User, :perform_action, {'id' => u.id, 'method' => 'remember_starred_board!', 'arguments' => [b.id]})).to be_truthy
    end
    
    it "should save when star! is called" do
      u = User.create
      b = Board.new(:user => u)
      expect(b.id).to eq(nil)
      b.star(u, true)
      expect(b.id).to eq(nil)
      b.star!(u, true)
      expect(b.id).not_to eq(nil)
    end
    
    it "should override whodunnit when star! is called" do
      PaperTrail.whodunnit = "nunya"
      u = User.create
      b = Board.create(user: u)
      u2 = User.create
      b.star!(u2, true)
      expect(b.settings['starred_user_ids']).to eq([u2.global_id])
      expect(b.versions.length).to eq(1)
      expect(b.versions.map(&:whodunnit)).to eq(['nunya'])
    end
  end

  describe "stars" do
    it "should always return a value" do
      b = Board.new
      expect(b.stars).to eq(0)
      b.settings = {}
      b.settings['stars'] = 4
      expect(b.stars).to eq(4)
    end
  end

  describe "generate_stats" do
    it "should generate statistics" do
      b = Board.new(settings: {})
      b.generate_stats
      expect(b.settings['stars']).to eq(0)
      expect(b.settings['forks']).to eq(0)
      expect(b.settings['home_uses']).to eq(0)
      expect(b.settings['recent_home_uses']).to eq(0)
      expect(b.settings['uses']).to eq(0)
      expect(b.settings['recent_uses']).to eq(0)
      expect(b.settings['non_author_uses']).to eq(0)
      expect(b.popularity).to eq(0)
      expect(b.home_popularity).to eq(0)
    end
    
    it "should lookup connections" do
      u = User.create
      b = Board.create(:user => u)
      3.times do
        UserBoardConnection.create(:board_id => b.id, :home => true, :user_id => 98765)
      end
      UserBoardConnection.create(:board_id => b.id, :user_id => u.id)
      b.settings['starred_user_ids'] = [1,2]
      b.settings['buttons'] = [{}]
      b.generate_stats
      expect(b.settings['stars']).to eq(2)
      expect(b.settings['forks']).to eq(0)
      expect(b.settings['home_uses']).to eq(3)
      expect(b.settings['recent_home_uses']).to eq(3)
      expect(b.settings['uses']).to eq(4)
      expect(b.settings['recent_uses']).to eq(4)
      expect(b.settings['non_author_uses']).to eq(3)
      expect(b.popularity).to eq(36)
      expect(b.any_upstream).to eq(false)
      expect(b.home_popularity).to eq(34)
    end
  end

  describe "generate_download" do
    it "should raise if an invalid type is provided" do
      b = Board.new
      expect { b.generate_download(nil, 'bacon', {}) }.to raise_error(Progress::ProgressError, "Unexpected download type, bacon")
    end
    
    it "should raise if conversion fails" do
      b = Board.new
      expect(Converters::Utils).to receive(:board_to_remote).with(b, nil, {
        'file_type' => 'obf', 
        'include' => 'this', 
        'headerless' => false, 
        'text_on_top' => false, 
        'transparent_background' => false,
        'text_only' => false,
        'text_case' => nil,
        'font' => nil
      }).and_return(nil)
      expect { b.generate_download(nil, 'obf', {}) }.to raise_error(Progress::ProgressError, "No URL generated")
    end
    
    it "should return the download URL on success" do
      b = Board.new
      expect(Converters::Utils).to receive(:board_to_remote).with(b, nil, {
        'file_type' => 'obf', 
        'include' => 'this', 
        'headerless' => false, 
        'text_on_top' => false, 
        'transparent_background' => false,
        'text_only' => false,
        'text_case' => nil,
        'font' => nil
      }).and_return("http://www.file.com")
      expect(b.generate_download(nil, 'obf', {})).to eq({:download_url => "http://www.file.com"})
    end
    
    it "should periodically update progress" do
      b = Board.new
      expect(Converters::Utils).to receive(:board_to_remote).with(b, nil, {
        'file_type' => 'obf', 
        'include' => 'this', 
        'headerless' => false, 
        'text_on_top' => false, 
        'transparent_background' => false,
        'text_only' => false,
        'text_case' => nil,
        'font' => nil
      }).and_return("http://www.file.com")
      expect(Progress).to receive(:update_current_progress).with(0.03, :generating_files)
      b.generate_download(nil, 'obf', {})
    end
    
    it "should allow an unauthenticated user" do
      b = Board.new
      expect(Converters::Utils).to receive(:board_to_remote).with(b, nil, {
        'file_type' => 'obf', 
        'include' => 'this', 
        'headerless' => false, 
        'text_on_top' => false, 
        'transparent_background' => false,
        'text_only' => false,
        'text_case' => nil,
        'font' => nil
      }).and_return("http://www.file.com")
      expect(b.generate_download(nil, 'obf', {})).to eq({:download_url => "http://www.file.com"})
    end
  end

  describe "generate_defaults" do
    it "should generate default values" do
      b = Board.new
      b.generate_defaults
      expect(b.settings['name']).to eq('Unnamed Board')
      expect(b.settings['grid']['rows']).to eq(2)
      expect(b.settings['grid']['columns']).to eq(4)
      expect(b.settings['grid']['order']).to eq([[nil, nil, nil, nil], [nil, nil, nil, nil]])
      expect(b.settings['immediately_downstream_board_ids']).to eq([])
      expect(b.search_string).to eq("unnamed board    locale:")
      expect(b.settings['image_url']).to eq(Board::DEFAULT_ICON)
    end
    
    it "should not override existing values" do
      b = Board.new
      b.settings = {}
      b.settings['name'] = 'Friends and Romans'
      b.settings['description'] = "A good little board"
      b.settings['grid'] = {}
      b.settings['grid']['rows'] = 3
      b.settings['grid']['columns'] = 5
      b.settings['locale'] = 'es'
      
      b.generate_defaults
      expect(b.settings['name']).to eq('Friends and Romans')
      expect(b.settings['description']).to eq("A good little board")
      expect(b.settings['grid']['rows']).to eq(3)
      expect(b.settings['grid']['columns']).to eq(5)
      expect(b.settings['grid']['order']).to eq([[nil, nil, nil, nil, nil], [nil, nil, nil, nil, nil], [nil, nil, nil, nil, nil]])
      expect(b.settings['immediately_downstream_board_ids']).to eq([])
      expect(b.search_string).to eq("friends and romans a good little board   locale:es")
    end
    
    it "should enforce proper format/dimensions for grid value" do
      b = Board.new
      b.settings = {}
      b.settings['grid'] = {'rows' => 2, 'columns' => 3}
      b.generate_defaults
      expect(b.settings['grid']['order']).to eq([[nil, nil, nil], [nil, nil, nil]])
      
      b.settings['grid'] = {'rows' => 2, 'columns' => 2, 'order' => [[1,2,3,4,5],[2,3,4,5,6],[3,4,5,6,7],[4,5,6,7,8]]}
      b.generate_defaults
      expect(b.settings['grid']['order']).to eq([[1,2],[2,3]])
    end
    
    it "should set immediate_downstream_board_ids" do
      b = Board.new
      b.settings = {}
      b.settings['buttons'] = [
        {'id' => 1},
        {'id' => 2, 'load_board' => {'id' => '12345'}},
        {'id' => 3, 'load_board' => {'id' => '12345'}},
        {'id' => 4, 'load_board' => {'id' => '23456'}}
      ]
      b.generate_defaults
      expect(b.settings['immediately_downstream_board_ids']).to eq(['12345', '23456'])
    end
    
    it "should track a revision if the content has changed" do
      b = Board.new
      b.generate_defaults
      expect(b.settings['revision_hashes'].length).to eq(1)
      expect(b.current_revision).to eq(b.settings['revision_hashes'][-1][0])
      expect(b.settings['revision_hashes'][0][1]).to be > 10.seconds.ago.to_i
      b.generate_defaults
      expect(b.settings['revision_hashes'].length).to eq(1)
      expect(b.current_revision).to eq(b.settings['revision_hashes'][-1][0])
      
      b.settings['buttons'] = [{'id' => 2, 'label' => 'bob'}]
      b.generate_defaults
      expect(b.settings['revision_hashes'].length).to eq(2)
      expect(b.current_revision).to eq(b.settings['revision_hashes'][-1][0])
      b.generate_defaults
      expect(b.settings['revision_hashes'].length).to eq(2)
      expect(b.current_revision).to eq(b.settings['revision_hashes'][-1][0])
      
      b.settings['buttons'] = [{'id' => 2, 'label' => 'bob'}]
      b.generate_defaults
      expect(b.settings['revision_hashes'].length).to eq(2)
      expect(b.current_revision).to eq(b.settings['revision_hashes'][-1][0])
      b.settings['grid']['rows'] = 4
      b.generate_defaults
      expect(b.settings['revision_hashes'].length).to eq(3)
      expect(b.current_revision).to eq(b.settings['revision_hashes'][-1][0])
    end
    
    it "should clear the search_string for unlisted boards" do
      b = Board.new
      b.settings = {}
      b.settings['name'] = 'Friends and Romans'
      b.settings['description'] = "A good little board"
      b.settings['grid'] = {}
      b.settings['grid']['rows'] = 3
      b.settings['grid']['columns'] = 5
      b.settings['locale'] = 'es'
      b.generate_defaults
      expect(b.search_string).to eq("friends and romans a good little board   locale:es")
      b.settings['unlisted'] = true
      b.generate_defaults
      expect(b.search_string).to eq(nil)
    end
  end
  
  describe "full_set_revision" do
    it "should push a revision hash change upstream when a new board is created" do
      u = User.create
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b1.settings['buttons'] = [{'id' => 1, 'load_board' => {'id' => b2.global_id}, 'label' => 'hair'}]
      b1.instance_variable_set('@buttons_changed', true)
      b1.save
      Worker.process_queues
      hash = b1.reload.settings['full_set_revision']
      current_hash = b1.current_revision
      b2.settings['buttons'] = [{'id' => 1, 'label' => 'feet'}]
      b2.instance_variable_set('@buttons_changed', true)
      b2.save
      Worker.process_queues
      expect(b1.reload.settings['full_set_revision']).to_not eq(hash)
      expect(b1.current_revision).to eq(current_hash)
    end
    
    it "should push a revision hash change upstream when a board is modified" do
      u = User.create
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b3 = Board.create(:user => u)
      b4 = Board.create(:user => u)
      b1.settings['buttons'] = [{'id' => 1, 'label' => 'cheese', 'load_board' => {'id' => b3.global_id}}]
      b1.instance_variable_set('@buttons_changed', true)
      b1.save
      b2.settings['buttons'] = [{'id' => 1, 'label' => 'cheese', 'load_board' => {'id' => b3.global_id}}]
      b2.instance_variable_set('@buttons_changed', true)
      b2.save
      b3.settings['buttons'] = [{'id' => 3, 'label' => 'chicken', 'load_board' => {'id' => b4.global_id}}]
      b3.instance_variable_set('@buttons_changed', true)
      b3.save
      Worker.process_queues
      hash1 = b1.reload.settings['full_set_revision']
      current1 = b1.current_revision
      hash2 = b2.reload.settings['full_set_revision']
      current2 = b2.current_revision
      hash3 = b3.reload.settings['full_set_revision']
      current3 = b3.current_revision
      b4.settings['buttons'] = [{'id' => 'asdf', 'label' => 'friend'}]
      b4.instance_variable_set('@buttons_changed', true)
      b4.save
      Worker.process_queues
      Worker.process_queues
      expect(b1.reload.settings['full_set_revision']).to_not eq(hash1)
      expect(b1.current_revision).to eq(current1)
      expect(b2.reload.settings['full_set_revision']).to_not eq(hash2)
      expect(b2.current_revision).to eq(current2)
      expect(b3.reload.settings['full_set_revision']).to_not eq(hash3)
      expect(b3.current_revision).to eq(current3)
    end
    
    it "should not push a revision has change downstream" do
      u = User.create
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b1.settings['buttons'] = [{'id' => 1, 'label' => 'art', 'load_board' => {'id' => b2.global_id}}]
      b1.instance_variable_set('@buttons_changed', true)
      b1.save
      Worker.process_queues
      expect(b1.reload.settings['downstream_board_ids']).to eq([b2.global_id])
      hash1 = b1.reload.settings['full_set_revision']
      current1 = b1.current_revision
      hash2 = b2.reload.settings['full_set_revision']
      current2 = b2.current_revision
      b1.settings['buttons'] = [{'id' => 1, 'label' => 'artist', 'load_board' => {'id' => b2.global_id}}]
      b1.instance_variable_set('@buttons_changed', true)
      b1.save
      Worker.process_queues
      expect(b1.reload.settings['full_set_revision']).to_not eq(hash1)
      expect(b1.current_revision).to_not eq(current1)
      expect(b2.reload.settings['full_set_revision']).to eq(hash2)
      expect(b2.current_revision).to eq(current2)
    end
    
    it "should update for an unlinked board when it is modified" do
      u = User.create
      b = Board.create(:user => u)
      expect(b.settings['full_set_revision']).to eq(nil)
      hash = b.full_set_revision
      current = b.current_revision
      b.settings['buttons'] = [{'id' => 1, 'label' => 'choker'}]
      b.instance_variable_set('@buttons_changed', true)
      b.save
      Worker.process_queues
      expect(b.full_set_revision).to_not eq(hash)
      expect(b.current_revision).to_not eq(current)
    end
  end

  describe "labels" do
    it "should grab a list of labels using the grid of buttons from left to right" do
      b = Board.new
      b.settings = {}
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'a'},
        {'id' => 2, 'label' => 'b'},
        {'id' => 3, 'label' => 'c'}
      ]
      b.settings['grid'] = {
        'rows' => 2,
        'columns' => 4,
        'order' => [
          [1, 1, nil, nil],
          [2, 1, 3, nil]
        ]
      }
      expect(b.labels).to eq("a, b, a, a, c")
    end
  end

  describe "buttons_and_images" do
    it "should return a cached value if there is one" do
      b = Board.new
      expect(b).to receive(:get_cached).with('buttons_and_images/nobody').and_return({a: 1})
      expect(b.buttons_and_images_for(nil)).to eq({a: 1})

      u = User.create
      expect(b).to receive(:get_cached).with("buttons_and_images/#{u.cache_key}").and_return({b: 1})
      expect(b.buttons_and_images_for(u)).to eq({b: 1})
    end

    it "should call cached_copy_urls to check for cached urls" do
      b = Board.new
      expect(b).to receive(:get_cached).with('buttons_and_images/nobody').and_return(nil)
      expect(ButtonImage).to receive(:cached_copy_urls).with([], nil, nil, [])
      b.buttons_and_images_for(nil)
    end

    it "should map images and sounds to json and return the result" do
      u = User.create
      User.purchase_extras({'user_id' => u.global_id})
      u.reload
      b = Board.create(user: u)
      expect(b).to receive(:get_cached).with("buttons_and_images/#{u.cache_key}").and_return(nil)
      bi1 = ButtonImage.create(user: u, board: b, settings: {'protected' => true, 'protected_source' => 'pcs'}, url: 'http://www.example.com')
      bi2 = ButtonImage.create(user: u, board: b, settings: {'protected' => true, 'protected_source' => 'abs'}, url: 'http://www.example.com')
      bs1 = ButtonSound.create(user: u, board: b)
      expect(b).to receive(:button_images).and_return([bi1, bi2])
      expect(b).to receive(:button_sounds).and_return([bs1])
      expect(JsonApi::Image).to receive(:as_json).with(bi1, :allowed_sources => ['pcs']).and_return({'bi1' => true})
      expect(JsonApi::Image).to receive(:as_json).with(bi2, :allowed_sources => ['pcs']).and_return({'bi2' => true})
      expect(JsonApi::Sound).to receive(:as_json).with(bs1).and_return({'bs1' => true})
      expect(b.buttons_and_images_for(u)).to eq({
        'images' => [
          {'bi1' => true}, {'bi2' => true}
        ],
        'sounds' => [
          {'bs1' => true}
        ]
      })
    end

    it "should cache the result" do
      u = User.create
      User.purchase_extras({'user_id' => u.global_id})
      u.reload
      b = Board.create(user: u)
      expect(b).to receive(:get_cached).with("buttons_and_images/#{u.cache_key}").and_return(nil)
      bi1 = ButtonImage.create(user: u, board: b, settings: {'protected' => true, 'protected_source' => 'pcs'}, url: 'http://www.example.com')
      bi2 = ButtonImage.create(user: u, board: b, settings: {'protected' => true, 'protected_source' => 'abs'}, url: 'http://www.example.com')
      bs1 = ButtonSound.create(user: u, board: b)
      expect(b).to receive(:button_images).and_return([bi1, bi2])
      expect(b).to receive(:button_sounds).and_return([bs1])
      expect(JsonApi::Image).to receive(:as_json).with(bi1, :allowed_sources => ['pcs']).and_return({'bi1' => true})
      expect(JsonApi::Image).to receive(:as_json).with(bi2, :allowed_sources => ['pcs']).and_return({'bi2' => true})
      expect(JsonApi::Sound).to receive(:as_json).with(bs1).and_return({'bs1' => true})
      expect(b).to receive(:set_cached).with("buttons_and_images/#{u.cache_key}", {"images"=>[{"bi1"=>true}, {"bi2"=>true}], "sounds"=>[{"bs1"=>true}]})
      expect(b.buttons_and_images_for(u)).to eq({
        'images' => [
          {'bi1' => true}, {'bi2' => true}
        ],
        'sounds' => [
          {'bs1' => true}
        ]
      })
    end

    it "should only return allowed protected sources" do
      u = User.create
      User.purchase_extras({'user_id' => u.global_id})
      u.reload
      b = Board.create(user: u)
      expect(b).to receive(:get_cached).with("buttons_and_images/#{u.cache_key}").and_return(nil)
      bi1 = ButtonImage.create(user: u, board: b, settings: {'protected' => true, 'protected_source' => 'pcs'}, url: 'http://www.example.com')
      bi2 = ButtonImage.create(user: u, board: b, settings: {'protected' => true, 'protected_source' => 'abs'}, url: 'http://www.example.com')
      bs1 = ButtonSound.create(user: u, board: b)
      expect(b).to receive(:button_images).and_return([bi1, bi2])
      expect(b).to receive(:button_sounds).and_return([bs1])
      expect(JsonApi::Image).to receive(:as_json).with(bi1, :allowed_sources => ['pcs']).and_return({'bi1' => true})
      expect(JsonApi::Image).to receive(:as_json).with(bi2, :allowed_sources => ['pcs']).and_return({'bi2' => true})
      expect(JsonApi::Sound).to receive(:as_json).with(bs1).and_return({'bs1' => true})
      expect(b).to receive(:set_cached).with("buttons_and_images/#{u.cache_key}", {"images"=>[{"bi1"=>true}, {"bi2"=>true}], "sounds"=>[{"bs1"=>true}]})
      expect(b.buttons_and_images_for(u)).to eq({
        'images' => [
          {'bi1' => true}, {'bi2' => true}
        ],
        'sounds' => [
          {'bs1' => true}
        ]
      })
    end

    it "should allow protected sources used by supervisees" do
      u = User.create
      u2 = User.create
      User.link_supervisor_to_user(u, u2)
      User.purchase_extras({'user_id' => u2.global_id})
      u.reload
      u2.reload

      b = Board.create(user: u)
      expect(b).to receive(:get_cached).with("buttons_and_images/#{u.cache_key}").and_return(nil)
      bi1 = ButtonImage.create(user: u, board: b, settings: {'protected' => true, 'protected_source' => 'pcs'}, url: 'http://www.example.com')
      bi2 = ButtonImage.create(user: u, board: b, settings: {'protected' => true, 'protected_source' => 'abs'}, url: 'http://www.example.com')
      bi3 = ButtonImage.create(user: u, board: b, settings: {'protected' => true, 'protected_source' => 'cheese'}, url: 'http://www.example.com')
      expect(b).to receive(:button_images).and_return([bi1, bi2, bi3])
      expect(JsonApi::Image).to receive(:as_json).with(bi1, :allowed_sources => ['pcs']).and_return({'bi1' => true})
      expect(JsonApi::Image).to receive(:as_json).with(bi2, :allowed_sources => ['pcs']).and_return({'bi2' => true})
      expect(JsonApi::Image).to receive(:as_json).with(bi3, :allowed_sources => ['pcs']).and_return({'bi3' => true})
      expect(b).to receive(:set_cached).with("buttons_and_images/#{u.cache_key}", {"images"=>[{"bi1"=>true}, {"bi2"=>true}, {'bi3' => true}], "sounds"=>[]})
      expect(b.buttons_and_images_for(u)).to eq({
        'images' => [
          {'bi1' => true}, {'bi2' => true}, {'bi3' => true}
        ],
        'sounds' => []
      })
    end
  end

  describe "current_revision" do
    it "should return the current_revision attribute if set, otherwise retrieve it from settings" do
       b = Board.new
       expect(b.current_revision).to eq(nil)
       
       b.current_revision = 'asdfhjk'
       expect(b.current_revision).to eq('asdfhjk')
       
       b.current_revision = nil
       b.settings = {'revision_hashes' => [['qwert']]}
       expect(b.current_revision).to eq('qwert')
    end
  end

  describe "populate_buttons_from_labels" do
    it "should add new buttons with the specified labels" do
      b = Board.new
      b.generate_defaults
      b.settings['buttons'] = [{'id' => 4}]
      b.populate_buttons_from_labels("a,b,c,d,e\nf,g\nbacon and eggs,t,q", 'columns')
      expect(b.settings['buttons'][1]).to eq({'id' => 5, 'label' => "a", 'suggest_symbol' => true})
      expect(b.settings['buttons'][2]).to eq({'id' => 6, 'label' => "b", 'suggest_symbol' => true})
      expect(b.settings['buttons'][3]).to eq({'id' => 7, 'label' => "c", 'suggest_symbol' => true})
      expect(b.settings['buttons'][4]).to eq({'id' => 8, 'label' => "d", 'suggest_symbol' => true})
      expect(b.settings['buttons'][5]).to eq({'id' => 9, 'label' => "e", 'suggest_symbol' => true})
      expect(b.settings['buttons'][6]).to eq({'id' => 10, 'label' => "f", 'suggest_symbol' => true})
      expect(b.settings['buttons'][7]).to eq({'id' => 11, 'label' => "g", 'suggest_symbol' => true})
      expect(b.settings['buttons'][8]).to eq({'id' => 12, 'label' => "bacon and eggs", 'suggest_symbol' => true})
      expect(b.settings['buttons'][9]).to eq({'id' => 13, 'label' => "t", 'suggest_symbol' => true})
      expect(b.settings['buttons'][10]).to eq({'id' => 14, 'label' => "q", 'suggest_symbol' => true})
      expect(b.settings['grid']['order']).to eq([[5, 7, 9, 11], [6, 8, 10, 12]])
    end

    it "should add new buttons with the specified labels in row-first order" do
      b = Board.new
      b.generate_defaults
      b.settings['buttons'] = [{'id' => 4}]
      b.populate_buttons_from_labels("a,b,c,d,e\nf,g\nbacon and eggs,t,q", 'rows')
      expect(b.settings['buttons'][1]).to eq({'id' => 5, 'label' => "a", 'suggest_symbol' => true})
      expect(b.settings['buttons'][2]).to eq({'id' => 6, 'label' => "b", 'suggest_symbol' => true})
      expect(b.settings['buttons'][3]).to eq({'id' => 7, 'label' => "c", 'suggest_symbol' => true})
      expect(b.settings['buttons'][4]).to eq({'id' => 8, 'label' => "d", 'suggest_symbol' => true})
      expect(b.settings['buttons'][5]).to eq({'id' => 9, 'label' => "e", 'suggest_symbol' => true})
      expect(b.settings['buttons'][6]).to eq({'id' => 10, 'label' => "f", 'suggest_symbol' => true})
      expect(b.settings['buttons'][7]).to eq({'id' => 11, 'label' => "g", 'suggest_symbol' => true})
      expect(b.settings['buttons'][8]).to eq({'id' => 12, 'label' => "bacon and eggs", 'suggest_symbol' => true})
      expect(b.settings['buttons'][9]).to eq({'id' => 13, 'label' => "t", 'suggest_symbol' => true})
      expect(b.settings['buttons'][10]).to eq({'id' => 14, 'label' => "q", 'suggest_symbol' => true})
      expect(b.settings['grid']['order']).to eq([[5, 6, 7, 8], [9, 10, 11, 12]])
    end
    
    it "should put the new button in its proper location on the grid if there is one" do
      b = Board.new
      b.generate_defaults
      b.settings['buttons'] = [{'id' => 4}]
      b.populate_buttons_from_labels("a,b,c,d,e\nf,g\nbacon and eggs,t,q", 'columns')
      expect(b.settings['grid']['order']).to eq([[5, 7, 9, 11],[6, 8, 10, 12]])
    end
  end
  
  describe "private boards" do
#     it "should not allow creating a private board without a premium user account" do
#       u = User.create(:expires_at => 3.days.ago)
#       res = Board.process_new({:public => false}, {:user => u})
#       expect(res.errored?).to eql(true)
#       expect(res.processing_errors).to eq(["only premium users can make boards private"])
#     end
    
#     it "should not allow changing a board to private without a premium user account" do
#       u = User.create(:expires_at => 3.days.ago)
#       b = Board.create(:user => u, :public => true)
#       expect(u.premium?).to eql(false)
#       res = b.process({:public => false}, {:user => u})
#       expect(res).to eql(false)
#       expect(b.processing_errors).to eq(["only premium users can make boards private"])
#     end
    
    it "should allow making a private board public without a premium user account" do
      u = User.create(:expires_at => 3.days.ago)
      b = Board.create(:user => u, :public => false)
      expect { b.process({:public => true}, {:user => u}) }.to_not raise_error
    end
    
    it "should allow creating a public board without a premium user account" do
      u = User.create(:expires_at => 3.days.ago)
      expect { Board.process_new({:public => true}, {:user => u}) }.to_not raise_error
    end
    
    it "should allow updating a private board without a premium user account" do
      u = User.create(:expires_at => 3.days.ago)
      b = Board.create(:user => u, :public => false)
      expect { b.process({:title => "ok"}, {:user => u}) }.to_not raise_error
      expect { b.process({:public => false}, {:user => u}) }.to_not raise_error
    end
    
    it "should allow premium users to create and update private boards" do
      u = User.create
      expect(u.premium?).to eq(true)
      expect { Board.process_new({:public => false}, {:user => u}) }.to_not raise_error
      b = Board.create(:user => u, :public => true)
      expect { b.process({:public => false}, {:user => u}) }.to_not raise_error
    end
  end

  describe "post processing" do
    it "should call map images" do
      u = User.create
      b = Board.new(:user => u)
      expect(b).to receive(:map_images)
      b.save
    end
    
    it "should schedule downstream tracking only if specified" do
      u = User.create
      b = Board.new(:user => u)
      b.save
      expect(Worker.scheduled?(Board, 'perform_action', {'id' => b.id, 'method' => 'track_downstream_boards!', 'arguments' => [[], nil, Time.now.to_i]})).to eq(true)
      Worker.flush_queues
      b.instance_variable_set('@track_downstream_boards', false)
      b.save
      expect(Worker.scheduled?(Board, 'perform_action', {'id' => b.id, 'method' => 'track_downstream_boards!', 'arguments' => [[], nil, Time.now.to_i]})).to eq(false)
      Worker.flush_queues
      b.instance_variable_set('@buttons_changed', true)
      b.instance_variable_set('@button_links_changed', true)
      b.save
      expect(Worker.scheduled?(Board, 'perform_action', {'id' => b.id, 'method' => 'track_downstream_boards!', 'arguments' => [[], true, Time.now.to_i]})).to eq(true)
      Worker.flush_queues
      
      b.instance_variable_set('@track_downstream_boards', true)
      b.save
      expect(Worker.scheduled?(Board, 'perform_action', {'id' => b.id, 'method' => 'track_downstream_boards!', 'arguments' => [[], nil, Time.now.to_i]})).to eq(true)
    end
  end
  
  describe "board changed notifications" do
    it "should alert connected users when the board changes" do
      u = User.create
      b = Board.create(:user => u)
      u.settings['preferences']['home_board'] = {'id' => b.global_id, 'key' => b.key }
      u.save
      
      expect(b).to receive(:notify) do |key, hash|
        expect(key).to eq('board_buttons_changed')
        expect(hash['revision']).not_to eq(nil)
      end
      b.process({'buttons' => [
        {'id' => 1},
        {'id' => 2, 'load_board' => {'id' => '12345'}},
        {'id' => 3, 'load_board' => {'id' => '12345'}},
        {'id' => 4, 'load_board' => {'id' => '23456'}}
      ]})
    end

    it "should add to the user's notification list when the board changes" do
      u = User.create
      u2 = User.create
      b = Board.create(:user => u)
      u.settings['preferences']['home_board'] = {'id' => b.global_id, 'key' => b.key }
      u.save
      Worker.process_queues
      
      b.settings['buttons'] = [
        {'id' => 1},
        {'id' => 2, 'load_board' => {'id' => '12345'}},
        {'id' => 3, 'load_board' => {'id' => '12345'}},
        {'id' => 4, 'load_board' => {'id' => '23456'}}
      ]
      b.instance_variable_set('@buttons_changed', true)
      b.save
      Worker.process_queues

      expect(u.reload.settings['user_notifications']).to eq([{
        'id' => b.global_id,
        'type' => 'board_buttons_changed',
        'for_user' => true,
        'for_supervisees' => [],
        'previous_revision' => b.settings['revision_hashes'][-2][0],
        'name' => b.settings['name'],
        'key' => b.key,
        'occurred_at' => b.reload.updated_at.iso8601,
        'added_at' => Time.now.utc.iso8601
      }])
      expect(u2.reload.settings['user_notifications']).to eq(nil)
    end
    
    it "should alert supervisors of connected users when the board changes" do
      u = User.create
      u2 = User.create
      u3 = User.create
      User.link_supervisor_to_user(u3, u)
      b = Board.create(:user => u)
      u.settings['preferences']['home_board'] = {'id' => b.global_id, 'key' => b.key }
      u.save
      Worker.process_queues
      
      b.settings['buttons'] = [
        {'id' => 1},
        {'id' => 2, 'load_board' => {'id' => '12345'}},
        {'id' => 3, 'load_board' => {'id' => '12345'}},
        {'id' => 4, 'load_board' => {'id' => '23456'}}
      ]
      b.instance_variable_set('@buttons_changed', true)
      b.save
      Worker.process_queues

      expect(u.reload.settings['user_notifications']).to eq([{
        'id' => b.global_id,
        'type' => 'board_buttons_changed',
        'for_user' => true,
        'for_supervisees' => [],
        'previous_revision' => b.settings['revision_hashes'][-2][0],
        'name' => b.settings['name'],
        'key' => b.key,
        'occurred_at' => b.reload.updated_at.iso8601,
        'added_at' => Time.now.utc.iso8601
      }])
      expect(u2.reload.settings['user_notifications']).to eq(nil)
      expect(u3.reload.settings['user_notifications']).to eq([{
        'id' => b.global_id,
        'type' => 'board_buttons_changed',
        'for_user' => false,
        'for_supervisees' => [u.user_name],
        'previous_revision' => b.settings['revision_hashes'][-2][0],
        'name' => b.settings['name'],
        'key' => b.key,
        'occurred_at' => b.reload.updated_at.iso8601,
        'added_at' => Time.now.utc.iso8601
      }])
    end
    
    it "should not schedule track_boards when notifying users of board changes" do
      u = User.create
      u2 = User.create
      b = Board.create(:user => u)
      u.settings['preferences']['home_board'] = {'id' => b.global_id, 'key' => b.key }
      u.save
      Worker.process_queues
      Worker.process_queues

      b.settings['buttons'] = [
        {'id' => 1},
        {'id' => 2, 'load_board' => {'id' => '12345'}},
        {'id' => 3, 'load_board' => {'id' => '12345'}},
        {'id' => 4, 'load_board' => {'id' => '23456'}}
      ]
      b.instance_variable_set('@buttons_changed', true)
      b.save
      expect(Worker.scheduled_for?(:slow, User, :perform_action, {'id' => u.id, 'method' => 'track_boards', 'arguments' => [true]})).to eq(false)
      expect(Worker.scheduled_for?(:slow, User, :perform_action, {'id' => u2.id, 'method' => 'track_boards', 'arguments' => [true]})).to eq(false)
      Worker.process_queues
      expect(Worker.scheduled_for?(:slow, User, :perform_action, {'id' => u.id, 'method' => 'track_boards', 'arguments' => [true]})).to eq(false)
      expect(Worker.scheduled_for?(:slow, User, :perform_action, {'id' => u2.id, 'method' => 'track_boards', 'arguments' => [true]})).to eq(false)

      expect(u.reload.settings['user_notifications'].length).to eq(1)
      expect(u2.reload.settings['user_notifications']).to eq(nil)
    end
    
    it "should not alert when the board buttons haven't actually changed" do
      u = User.create
      b = Board.create(:user => u)
      expect(b).not_to receive(:notify)
      u.settings['preferences']['home_board'] = {'id' => b.global_id, 'key' => b.key }
      u.save
      
      b.process({})
    end
  end

  describe "require_key" do
    it "should fail if no user is provided" do
      b = Board.new
      expect { b.require_key }.to raise_error("user required")
    end
    
    it "should generate a key if none is provided" do
      u = User.create
      b = Board.new(:user => u)
      b.require_key
      expect(b.key).to eq('no-name/board')
      
      b.key = nil
      b.settings = {'name' => 'alfalfa'}
      b.require_key
      expect(b.key).to eq('no-name/alfalfa')
    end
    
    it "shouldn't call generate_key if key is already set" do
      b = Board.new
      b.key = 'qwert'
      expect(b).not_to receive(:generate_key)
      b.require_key
    end
  end

  describe "cached_user_name" do
    it "should return the name part of the board key, if available" do
      b = Board.new
      expect(b.cached_user_name).to eq(nil)
      b.key = "asdf"
      expect(b.cached_user_name).to eq('asdf')
      b.key = "user/bacon"
      expect(b.cached_user_name).to eq("user")
    end
  end
  
  describe "process_buttons" do
    it "should update the buttons settings attribute" do
      b = Board.new
      b.settings ||= {}
      b.process_buttons([
        {'id' => '1_2', 'label' => 'hat'}
      ], nil)
      expect(b.settings['buttons']).not_to eq(nil)
      expect(b.settings['buttons'].length).to eq(1)
      expect(b.settings['buttons'][0]).to eq({
        'id' => '1_2',
        'label' => 'hat'
      })
    end
    
    it "should filter out unexpected options" do
      b = Board.new
      b.settings ||= {}
      b.process_buttons([
        {'id' => '1_2', 'label' => 'hat', 'hidden' => true, 'chicken' => '1234'}
      ], nil)
      expect(b.settings['buttons']).not_to eq(nil)
      expect(b.settings['buttons'].length).to eq(1)
      expect(b.settings['buttons'][0]).to eq({
        'id' => '1_2',
        'label' => 'hat',
        'hidden' => true
      })
    end
    
    it "should remember link_disabled for only appropriate button types" do
      u1 = User.create
      b1 = Board.create!(:user => u1)
      b = Board.new
      b.settings ||= {}
      b.process_buttons([
        {'id' => '1_2', 'label' => 'hat', 'link_disabled' => true, 'chicken' => '1234'},
        {'id' => '1_3', 'label' => 'hat', 'link_disabled' => true, 'chicken' => '1234', 'url' => 'http://www.example.com'},
        {'id' => '1_4', 'label' => 'hat', 'link_disabled' => true, 'load_board' => {'id' => b1.global_id, 'key' => b1.key}},
        {'id' => '1_5', 'label' => 'hat', 'link_disabled' => true, 'chicken' => '1234', 'apps' => {}},
      ], u1)
      expect(b.settings['buttons']).not_to eq(nil)
      expect(b.settings['buttons'].length).to eq(4)
      expect(b.settings['buttons'][0]).to eq({
        'id' => '1_2',
        'label' => 'hat'
      })
      expect(b.settings['buttons'][1]).to eq({
        'id' => '1_3',
        'label' => 'hat',
        'link_disabled' => true,
        'url' => 'http://www.example.com'
      })
      expect(b.settings['buttons'][2]).to eq({
        'id' => '1_4',
        'label' => 'hat',
        'link_disabled' => true,
        'load_board' => {'id' => b1.global_id, 'key' => b1.key}
      })
      expect(b.settings['buttons'][3]).to eq({
        'id' => '1_5',
        'label' => 'hat',
        'link_disabled' => true,
        'apps' => {}
      })
    end
    
    it "should set @buttons_changed only if one or more buttons has changed" do
      b = Board.new
      b.settings ||= {}
      b.process_buttons([
        {'id' => '1_2', 'label' => 'hat', 'hidden' => true, 'chicken' => '1234'}
      ], nil)
      expect(b.settings['buttons']).not_to eq(nil)
      expect(b.settings['buttons'].length).to eq(1)
      expect(!!b.instance_variable_get('@buttons_changed')).to eq(true)
      b.instance_variable_set('@buttons_changed', false)
      b.process_buttons([
        {'id' => '1_2', 'label' => 'hat', 'hidden' => true, 'chicken' => '1234'}
      ], nil)
      expect(b.instance_variable_get('@buttons_changed')).to eq(false)
    end
    
    it "should check access permission for any newly-added linked boards" do
      u1 = User.create
      b1 = Board.create!(:user => u1)
      u2 = User.create
      b2 = Board.create!(:user => u2)
      u3 = User.create
      b3 = Board.create!(:user => u3)
      
      b = Board.new
      b.settings = {
        'buttons' => [
          {'id' => '1_1', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
        ]
      }
      b.process_buttons([
        {'id' => '1_1', 'label' => 'hat', 'load_board' => {'id' => b1.global_id, 'key' => b1.key}},
        {'id' => '1_2', 'label' => 'cat', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}},
        {'id' => '1_3', 'label' => 'fat', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
      ], u1)
      expect(b.settings['buttons']).not_to eq(nil)
      expect(b.settings['buttons'].length).to eq(3)
      expect(b.settings['buttons'][0]['id']).to eq('1_1')
      expect(b.settings['buttons'][0]['load_board']).not_to eq(nil)
      expect(b.settings['buttons'][1]['id']).to eq('1_2')
      expect(b.settings['buttons'][1]['load_board']).to eq(nil)
      expect(b.settings['buttons'][2]['id']).to eq('1_3')
      expect(b.settings['buttons'][2]['load_board']).not_to eq(nil)
    end
    
    it "should process translations from buttons" do
      b = Board.new
      b.settings ||= {}
      b.process_buttons([
        {'id' => '1_2', 'label' => 'hat', 'hidden' => true, 'chicken' => '1234', 'translations' => [
          {'locale' => 'en', 'label' => 'hat'},
          {'locale' => 'es', 'label' => 'hatzy', 'vocalization' => 'hatz'}
        ]}
      ], nil)
      expect(b.settings['buttons']).not_to eq(nil)
      expect(b.settings['buttons'].length).to eq(1)
      expect(b.settings['translations']).to eq({
        '1_2' => {
          'en' => {
            'label' => 'hat'
          },
          'es' => {
            'label' => 'hatzy',
            'vocalization' => 'hatz'
          }
        }
      })
    end
  end

  describe "process_params" do
    it "should raise an error unless a user is provided" do
      b = Board.new
      expect { b.process_params({}, {}) }.to raise_error("user required as board author")
      u = User.create
      expect { b.process_params({}, {:user => u}) }.to_not raise_error
      
      expect(b.user).not_to eq(nil)
      expect { b.process_params({}, {}) }.to_not raise_error
    end
    
    it "should ignore non-sent parameters" do
      u = User.create
      b = Board.new(:user => u)
      b.process_params({}, {})
      expect(b.settings['name']).to eq(nil)
      expect(b.settings['buttons']).to eq(nil)
      expect(b.key).to eq(nil)
    end
    
    it "should set last_updated" do
      u = User.create
      b = Board.new(:user => u)
      b.process_params({}, {})
      expect(b.settings['last_updated']).to eq(Time.now.iso8601)
    end

    it "should not set name column" do
      u = User.create
      b = Board.new(:user => u)
      b.process_params({'name' => 'bacon cheese'}, {})
      expect(b.name).to eq(nil)
      expect(b.settings['name']).to eq('bacon cheese')
    end
    
    it "should set settings" do
      u = User.create
      b = Board.new(:user => u)
      b.process_params({
        'name' => 'Fred',
        'grid' => {},
        'description' => 'Fred is my favorite board'
      }, {})
      expect(b.settings['name']).to eq("Fred")
      expect(b.settings['buttons']).to eq(nil)
      expect(b.settings['grid']).to eq({})
      expect(b.key).to eq(nil)
    end
    it "should only set key if provided as a non-user parameter" do
      u = User.create
      b = Board.new(:user => u)
      b.process_params({}, {:key => "tmp_ignore"})
      expect(b.key).to eq(nil)

      b.process_params({}, {:key => "something_good"})
      expect(b.key).to eq("no-name/something_good")
    end
    
    it "should sanitize board name and description" do
      u = User.create
      b = Board.create(:user => u)
      b.process({'name' => "<b>Coolness</b>", 'description' => "Something <a href='#'>fun</a>"})
      expect(b.settings['name']).to eq('Coolness')
      expect(b.settings['description']).to eq('Something fun')
    end
    
    it "should preserve the grid order correctly" do
      u = User.create
      b = Board.create(:user => u)
      b.process({
        'buttons' => [{'id' => 1, 'label' => 'friend'}, {'id' => 2, 'label' => 'send'}, {'id' => '3', 'label' => 'blend'}],
        'grid' => {
          'rows' => 3,
          'columns' => 3,
          'order' => [[nil,1,nil],[2,nil,3],[nil,nil,nil]]
        }
      })
      expect(b.settings['grid']['order']).to eq([[nil,1,nil],[2,nil,3],[nil,nil,nil]])
    end
    
    it "should not allow referencing a protected boards as parent board" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['protected'] = {'vocabulary' => true}
      b.save
      b2 = Board.create(:user => u)
      b2.process({
        'parent_board_id' => b.global_id
      })
      expect(b2.errored?).to eq(true)
      expect(b2.processing_errors).to eq(['cannot copy protected boards'])
    end
    
    it "should set visibility to public" do
      u = User.create
      b = Board.create(:user => u)
      b.process({'visibility' => 'public'})
      expect(b.public).to eq(true)
      expect(b.settings['unlisted']).to eq(false)
    end
    
    it "should set visibility to unlisted" do
      u = User.create
      b = Board.create(:user => u)
      b.process({'visibility' => 'unlisted'})
      expect(b.public).to eq(true)
      expect(b.settings['unlisted']).to eq(true)
    end
    
    it "should set visibility to private" do
      u = User.create
      b = Board.create(:user => u, :public => true)
      b.process({'visibility' => 'private'})
      expect(b.public).to eq(false)
      expect(b.settings['unlisted']).to eq(false)
    end
    
    it "should mark an update to visibility" do
      u = User.create
      b = Board.create(:user => u)
      b.process({'visibility' => 'public'})
      expect(b.public).to eq(true)
      expect(b.settings['unlisted']).to eq(false)
      expect(b.settings['edit_description']['notes']).to eq(['set to public'])
    end
    
    it "should tie to the source board's copy id if defined" do
      u = User.create
      b = Board.create(:user => u, :settings => {'copy_id' => '123456'})
      b2 = Board.process_new({
        'source_id' => b.global_id
      }, {'user' => u})
      expect(b2.settings['copy_id']).to eq('123456')
    end
    
    it "should ignore source_id on update" do
      u = User.create
      b = Board.create(:user => u, :settings => {'copy_id' => '123456'})
      b2 = Board.create(:user => u)
      expect(b2.settings['copy_id']).to eq(nil)
      b2.process({
        'source_id' => b.global_id
      })
      expect(b2.settings['copy_id']).to eq(nil)
    end

    it "should use the source board's id as the copy id if defined" do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.process_new({
        'source_id' => b.global_id
      }, {'user' => u})
      expect(b2.settings['copy_id']).to eq(b.global_id)
    end
    
    it "should not set the copy id if not allowed to edit the source board" do
      u = User.create
      u2 = User.create
      b = Board.create(:user => u, :settings => {'copy_id' => '123456'})
      b2 = Board.process_new({
        'source_id' => b.global_id
      }, {'user' => u2})
      expect(b2.settings['copy_id']).to eq(nil)
    end
  end

  it "should securely serialize settings" do
    u = User.create
    b = Board.new(:user => u)
    b.generate_defaults
    settings = b.settings
    expect(GoSecure::SecureJson).to receive(:dump).with(b.settings)
    b.save
  end
  
  describe "post_process" do
    it "should search for a better default icon if the default icon is being used" do
      u = User.create
      b = Board.create(:user => u)
      b.settings = {'name' => 'chicken and fries'}
      b.generate_defaults
      expect(b.settings['image_url']).to eq(Board::DEFAULT_ICON)
      expect(b.settings['default_image_url']).to eq(Board::DEFAULT_ICON)
      res = OpenStruct.new(:body => [{}, {'license' => 'CC By', 'image_url' => 'http://example.com/pic.png'}].to_json)
      expect(Typhoeus).to receive(:get).with("https://www.opensymbols.org/api/v1/symbols/search?q=chicken+and+fries", :ssl_verifypeer => false).and_return(res)
      b.save
      Worker.process_queues
      b.reload
      expect(b.settings['image_url']).to eq('http://example.com/pic.png')
      expect(b.settings['default_image_url']).to eq('http://example.com/pic.png')
    end
    
    it "should not search for a better default icon once it's already found a better default icon" do
      u = User.create
      b = Board.create(:user => u)
      b.settings = {'name' => 'chicken and fries'}
      b.generate_defaults
      expect(b.settings['image_url']).to eq(Board::DEFAULT_ICON)
      expect(b.settings['default_image_url']).to eq(Board::DEFAULT_ICON)
      res = OpenStruct.new(:body => [{}, {'license' => 'CC By', 'image_url' => 'http://example.com/pic.png'}].to_json)
      expect(Typhoeus).to receive(:get).with("https://www.opensymbols.org/api/v1/symbols/search?q=chicken+and+fries", :ssl_verifypeer => false).and_return(res)
      b.save
      Worker.process_queues
      b.reload
      expect(b.settings['image_url']).to eq('http://example.com/pic.png')
      expect(b.settings['default_image_url']).to eq('http://example.com/pic.png')
      
      b.process_params({'name' => 'cool people'}, {})
      expect(Typhoeus).not_to receive(:get)
      b.save
      Worker.process_queues
      b.reload
      expect(b.settings['image_url']).to eq('http://example.com/pic.png')
      expect(b.settings['default_image_url']).to eq('http://example.com/pic.png')

      expect(Typhoeus).not_to receive(:get)
      b.save
      Worker.process_queues
      b.reload
      expect(b.settings['image_url']).to eq('http://example.com/pic.png')
      expect(b.settings['default_image_url']).to eq('http://example.com/pic.png')
    end
    
    it "should not search for a better default icon if no name set for the board" do
      u = User.create
      b = Board.create(:user => u)
      b.generate_defaults
      expect(b.settings['image_url']).to eq(Board::DEFAULT_ICON)
      expect(b.settings['default_image_url']).to eq(Board::DEFAULT_ICON)
      expect(Typhoeus).not_to receive(:get)
      b.save
      Worker.process_queues
      b.reload
      expect(b.settings['image_url']).to eq(Board::DEFAULT_ICON)
      expect(b.settings['default_image_url']).to eq(Board::DEFAULT_ICON)
    end
    
    it "should not search for a better default icon if an icon has been manually set" do
      u = User.create
      b = Board.create(:user => u)
      b.settings = {'name' => 'chicken and fries'}
      b.generate_defaults
      expect(b.settings['image_url']).to eq(Board::DEFAULT_ICON)
      expect(b.settings['default_image_url']).to eq(Board::DEFAULT_ICON)
      b.process({'image_url' => 'http://example.com/pic.png'})
      expect(b.settings['image_url']).to eq('http://example.com/pic.png')
      expect(b.settings['default_image_url']).to eq(nil)
      
      expect(Typhoeus).not_to receive(:get)
      b.save
      Worker.process_queues
      b.reload
      expect(b.settings['image_url']).to eq('http://example.com/pic.png')
      expect(b.settings['default_image_url']).to eq(nil)
      
      b = Board.create(:user => u)
      b.settings = {'image_url' => 'http://example.com/pic2.png'}
      b.generate_defaults
      expect(b.settings['image_url']).to eq('http://example.com/pic2.png')
      expect(b.settings['default_image_url']).to eq(nil)
      
      expect(Typhoeus).not_to receive(:get)
      b.save
      Worker.process_queues
      b.reload
      expect(b.settings['image_url']).to eq('http://example.com/pic2.png')
      expect(b.settings['default_image_url']).to eq(nil)

      b = Board.create(:user => u)
      b.settings = {'image_url' => Board::DEFAULT_ICON}
      b.generate_defaults
      expect(b.settings['image_url']).to eq(Board::DEFAULT_ICON)
      expect(b.settings['default_image_url']).to eq(nil)
      
      expect(Typhoeus).not_to receive(:get)
      b.save
      Worker.process_queues
      b.reload
      expect(b.settings['image_url']).to eq(Board::DEFAULT_ICON)
      expect(b.settings['default_image_url']).to eq(nil)
    end
  end
  
  describe "cleanup on destroy" do
    it "should remove related records" do
      u = User.create
      b = Board.create(:user => u)
      expect(DeletedBoard).to receive(:process).with(b)
      b.destroy
      Worker.process_queues
    end
  end
  
  describe "find_copies_by" do
    it "should return nothing if no user provided" do
      u = User.create
      b = Board.create(:user => u)
      expect(b.find_copies_by(nil)).to eq([])
    end
    
    it "should return nothing if no matching board found" do
      u1 = User.create
      b1 = Board.create(:user => u1)
      u2 = User.create
      expect(b1.find_copies_by(u2)).to eq([])
    end
    
    it "should return a result if any found" do
      u1 = User.create
      b1 = Board.create(:user => u1)
      u2 = User.create
      b2 = Board.create(:user => u2, :parent_board_id => b1.id)
      expect(b1.find_copies_by(u2)).to eq([b2])
    end
    
    it "should return the most recent result" do
      u1 = User.create
      b1 = Board.create(:user => u1)
      u2 = User.create
      b2 = Board.create(:user => u2, :parent_board_id => b1.id)
      b3 = Board.create(:user => u2, :parent_board_id => b1.id)
      expect(b1.find_copies_by(u2)).to eq([b3, b2])
    end
    
    it "should include copies by supervisees, but list them after the user's" do
      u1 = User.create
      u2 = User.create
      u3 = User.create
      b1 = Board.create(:user => u1)
      b2 = Board.create(:user => u2, :parent_board_id => b1.id)
      b3 = Board.create(:user => u3, :parent_board_id => b1.id)
      expect(b1.find_copies_by(u2)).to eq([b2])
      
      User.link_supervisor_to_user(u2, u3)
      Worker.process_queues
      
      expect(b1.find_copies_by(u2)).to eq([b2, b3])
    end
  end
  
  describe "check_for_parts_of_speech" do
    it "should schedule call when board is processed" do
      u = User.create
      b = Board.create(:user => u)
      b.process({'buttons' => []})
      expect(Worker.scheduled?(Board, :perform_action, {'id' => b.id, 'method' => 'check_for_parts_of_speech', 'arguments' => []})).to be_truthy
    end
    
    it "should set part_of_speech for any buttons that don't have one set" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat'},
        {'id' => 2, 'label' => 'cat', 'part_of_speech' => 'verb'}
      ]
      b.save
      b.check_for_parts_of_speech
      expect(b.settings['buttons'][0]['part_of_speech']).to eq('noun')
      expect(b.settings['buttons'][0]['suggested_part_of_speech']).to eq('noun')
      expect(b.settings['buttons'][1]['part_of_speech']).to eq('verb')
      expect(b.settings['buttons'][1]['suggested_part_of_speech']).to eq(nil)
    end
    
    it "should not set part_of_speech for any buttons that have one set" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat'},
        {'id' => 2, 'label' => 'cat', 'part_of_speech' => 'verb'}
      ]
      b.save
      b.check_for_parts_of_speech
      expect(b.settings['buttons'][0]['part_of_speech']).to eq('noun')
      expect(b.settings['buttons'][0]['suggested_part_of_speech']).to eq('noun')
      expect(b.settings['buttons'][1]['part_of_speech']).to eq('verb')
      expect(b.settings['buttons'][1]['suggested_part_of_speech']).to eq(nil)
    end
    
    it "should record an event for any buttons that were manually set to something other than the suggested value" do
      RedisInit.default.del('overridden_parts_of_speech')
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat'},
        {'id' => 2, 'label' => 'cat', 'part_of_speech' => 'verb', 'suggested_part_of_speech' => 'noun'}
      ]
      b.save
      b.check_for_parts_of_speech
      expect(b.settings['buttons'][0]['part_of_speech']).to eq('noun')
      expect(b.settings['buttons'][0]['suggested_part_of_speech']).to eq('noun')
      expect(b.settings['buttons'][1]['part_of_speech']).to eq('verb')
      expect(b.settings['buttons'][1]['suggested_part_of_speech']).to eq('noun')
      
      words = RedisInit.default.hgetall('overridden_parts_of_speech')
      expect(words).not_to eq(nil)
      expect(words['cat-verb']).to eq("1")
      expect(words['cat']).to eq(nil)
    end
  end
  
  describe "edit_description" do
    it "should set proper edit description when known entries have changed" do
      u = User.create
      b = Board.create(:user => u)
      b.process(:name => "good board")
      expect(b.settings['edit_description']).not_to eq(nil)
      assert_timestamp(b.settings['edit_description']['timestamp'], Time.now.to_i)
    end
    
    it "should clear edit description on subsequent saves" do
      u = User.create
      b = Board.create(:user => u)
      b.process(:name => "good board")
      b.settings['edit_description']['timestamp'] = 5.seconds.ago.to_f
      b.save
      expect(b.settings['edit_description']).to eq(nil)
    end
    
    it "should set edit description when buttons are changed" do
      u = User.create
      b = Board.create(:user => u)
      b.process(:buttons => [{'id' => 1, 'label' => 'hat'}])
      expect(b.settings['edit_description']).not_to eq(nil)
      expect(b.settings['edit_description']['notes']).to eq(['modified buttons'])
    end
    
    it "should set edit description when description is changed" do
      u = User.create
      b = Board.create(:user => u)
      b.process(:description => "good board")
      expect(b.settings['edit_description']).not_to eq(nil)
      expect(b.settings['edit_description']['notes']).to eq(['updated the description'])
    end
    
    it "should set edit description when the grid is changed"
    
    it "should set edit description when the board name is changed" do
      u = User.create
      b = Board.create(:user => u)
      b.process(:name => "good board")
      expect(b.settings['edit_description']).not_to eq(nil)
      expect(b.settings['edit_description']['notes']).to eq(['renamed the board'])
    end
    
    it "should set edit description when the board license is changed" do
      u = User.create
      b = Board.create(:user => u)
      b.process(:license => {'type' => 'public_domain'})
      expect(b.settings['edit_description']).not_to eq(nil)
      expect(b.settings['edit_description']['notes']).to eq(['changed the license'])
    end
    
    it "should set edit description when the board image is changed" do
      u = User.create
      b = Board.create(:user => u)
      b.process(:image_url => "http://www.example.com/pic.png")
      expect(b.settings['edit_description']).not_to eq(nil)
      expect(b.settings['edit_description']['notes']).to eq(['changed the image'])
    end
    
    it "should set edit description when the board is changed to public or private" do
      u = User.create
      b = Board.create(:user => u)
      b.process(:public => true)
      expect(b.settings['edit_description']).not_to eq(nil)
      expect(b.settings['edit_description']['notes']).to eq(['set to public'])

      b.settings['edit_description']['timestamp'] = 6.seconds.ago.to_i
      b.process(:public => true)
      expect(b.settings['edit_description']).to eq(nil)

      b.process(:public => false)
      expect(b.settings['edit_description']).not_to eq(nil)
      expect(b.settings['edit_description']['notes']).to eq(['set to private'])

      b.settings['edit_description']['timestamp'] = 6.seconds.ago.to_i
      b.process(:public => false)
      expect(b.settings['edit_description']).to eq(nil)
    end
  end
  
  describe "import" do
    it "should convert boards" do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.create(:user => u)
      boards = [b, b2]
      expect(Converters::Utils).to receive(:remote_to_boards).with(u, 'http://www.example.com/board.obf').and_return(boards)
      res = Board.import(u.global_id, 'http://www.example.com/board.obf')
      expect(res.length).to eq(2)
      expect(res[0]['id']).to eq(b.global_id)
      expect(res[1]['id']).to eq(b2.global_id)
    end
  end
  
  describe "additional_webhook_codes" do
    it "should return empty list by default" do
      u = User.create
      b = Board.create(:user => u)
      expect(b.additional_webhook_record_codes('asdf', nil)).to eq([])
      expect(b.additional_webhook_record_codes('button_action', nil)).to eq([])
      expect(b.additional_webhook_record_codes('something', {'button_id' => 'asdf', 'user_id' => u.global_id})).to eq([])
      b.settings['buttons'] = [{
        'id' => '123'
      }]
      expect(b.additional_webhook_record_codes('button_action', {'button_id' => '123', 'user_id' => u.global_id})).to eq([])
    end
    
    it "should return the connect user_integration only if allowed" do
      u = User.create
      u2 = User.create
      u3 = User.create
      b = Board.create(:user => u)
      ui = UserIntegration.create(:user => u3, :settings => {'button_webhook_url' => 'http://www.example.com'})
      b.settings['buttons'] = [{}, {
        'id' => 'hat',
        'integration' => {'user_integration_id' => ui.global_id}
      }]
      expect(b.additional_webhook_record_codes('button_action', {'button_id' => 'hat', 'user_id' => u.global_id})).to eq([ui.record_code])
    end
  end
  
  describe "webhook_content" do
    it "should return nothing by default" do
      u = User.create
      b = Board.create(:user => u)
      expect(b.webhook_content(nil, nil, nil)).to eq("{}")
      expect(b.webhook_content('button_action', nil, nil)).to eq("{}")
      expect(b.webhook_content(nil, nil, {'button_id' => '123'})).to eq("{}")
      expect(b.webhook_content('button_action', nil, {'button_id' => '123', 'user_id' => u.global_id})).to eq("{}")
      b.settings['buttons'] = [{
        'id' => '123'
      }]
      expect(b.webhook_content('button_action', nil, {'button_id' => '123'})).to eq("{}")
    end
    
    it "should return button action information for a valid, authorized integration button" do
      u = User.create
      b = Board.create(:user => u)
      ui = UserIntegration.create(:user => u, :settings => {'button_webhook_url' => 'http://www.example.com'})
      b.settings['buttons'] = [{}, {
        'id' => '123',
        'integration' => {'user_integration_id' => ui.global_id}
      }]
      str = b.webhook_content('button_action', nil, {'button_id' => '123', 'user_id' => u.global_id})
      json = JSON.parse(str)
      expect(json['action']).to eq(nil)
      expect(json['placement_code']).to_not eq(nil)
      expect(json['user_code']).to_not eq(nil)
      expect(json['user_id']).to eq(nil)
    end
  end
  
  describe "update_affected_users" do
    it "should find and update all users attached to the board" do
      u = User.create
      b = Board.create(:user => u)
      u.settings['preferences']['home_board'] = {'id' => b.global_id}
      u.save
      Worker.process_queues
      Worker.process_queues
      User.where(:id => u.id).update_all(:updated_at => 2.months.ago)
      b.settings['buttons'] = [{'id' => 1, 'label' => 'whatever'}]
      b.instance_variable_set('@buttons_changed', true)
      b.save
      expect(u.reload.updated_at).to be < 2.weeks.ago
      Worker.process_queues
      expect(u.reload.updated_at).to be > 2.weeks.ago
    end
    
    it "should find and update supervisors of users attached to the board" do
      u = User.create
      u2 = User.create
      User.link_supervisor_to_user(u2, u)
      u.reload
      b = Board.create(:user => u)
      u.settings['preferences']['home_board'] = {'id' => b.global_id}
      u.save
      Worker.process_queues
      Worker.process_queues
      User.where(:id => [u.id, u2.id]).update_all(:updated_at => 2.months.ago)
      b.settings['buttons'] = [{'id' => 1, 'label' => 'whatever'}]
      b.save
      expect(u2.reload.updated_at).to be < 2.weeks.ago
      Worker.process_queues
      expect(u2.reload.updated_at).to be > 2.weeks.ago
    end
    
    it "should call 'track_boards' if it's a new board update" do
      u = User.create
      b = Board.create(:user => u)
      UserBoardConnection.create(:board_id => b.id, :user_id => u.id)
      list = [u]
      expect(User).to receive(:where).with(:id => [u.id.to_s]).and_return(list)
      expect(list).to receive(:update_all).and_return(true)
      expect(u).to receive(:track_boards)
      b.update_affected_users(true)
    end
    
    it "should not call 'track_boards' if it's not a new board update" do
      u = User.create
      b = Board.create(:user => u)
      UserBoardConnection.create(:board_id => b.id, :user_id => u.id)
      list = [u]
      expect(User).to receive(:where).with(:id => [u.id.to_s]).and_return(list)
      expect(list).to receive(:update_all).and_return(true)
      expect(u).to_not receive(:track_boards)
      b.update_affected_users(false)
    end
    
    it "should not update users if nothing has changed" do
      u = User.create
      b = Board.create(:user => u)
      u.settings['preferences']['home_board'] = {'id' => b.global_id}
      u.save
      Worker.process_queues
      Worker.process_queues
      Worker.process_queues
      User.where(:id => u.id).update_all(:updated_at => 2.months.ago)
      b.save
      expect(u.reload.updated_at).to be < 2.weeks.ago
      Worker.process_queues
      expect(u.reload.updated_at).to be < 2.weeks.ago
    end
  end
  
  describe "UserBoardConnection" do
    it "should touch connected users when a new sub-board of their home board is created" do
      u = User.create
      b = Board.create(:user => u)
      u.settings['preferences']['home_board'] = {'id' => b.global_id}
      u.save
      b2 = Board.create(:user => u)
      Worker.process_queues
      Worker.process_queues
      Worker.process_queues
      User.where(:id => u.id).update_all(:updated_at => 2.months.ago)
      b.settings['buttons'] = [{'id' => 1, 'label' => 'water', 'load_board' => {'id' => b2.global_id}}]
      b.instance_variable_set('@buttons_changed', true)
      b.save
      expect(u.reload.updated_at).to be < 2.weeks.ago
      Worker.process_queues
      u.reload
      expect(u.reload.updated_at).to be > 2.weeks.ago
    end
  
    it "should touch supervisors of connected users when a new sub-board of their home board is created" do
      u = User.create
      u2 = User.create
      User.link_supervisor_to_user(u2, u)
      b = Board.create(:user => u)
      u.settings['preferences']['home_board'] = {'id' => b.global_id}
      u.save
      b2 = Board.create(:user => u)
      Worker.process_queues
      Worker.process_queues
      Worker.process_queues
      User.where(:id => u2.id).update_all(:updated_at => 2.months.ago)
      b.settings['buttons'] = [{'id' => 1, 'label' => 'water', 'load_board' => {'id' => b2.global_id}}]
      b.instance_variable_set('@buttons_changed', true)
      b.save
      expect(u2.reload.updated_at).to be < 2.weeks.ago
      Worker.process_queues
      u.reload
      expect(u2.reload.updated_at).to be > 2.weeks.ago
    end
    
    it "should touch connected users when a sub-board of their home board is modified" do
      u = User.create
      b = Board.create(:user => u)
      u.settings['preferences']['home_board'] = {'id' => b.global_id}
      u.save
      b2 = Board.create(:user => u)
      b.settings['buttons'] = [{'id' => 1, 'label' => 'water', 'load_board' => {'id' => b2.global_id}}]
      b.instance_variable_set('@buttons_changed', true)
      b.save
      Worker.process_queues
      Worker.process_queues
      Worker.process_queues
      b2.settings['buttons'] = [{'id' => 1, 'label' => 'wishing'}]
      b2.instance_variable_set('@buttons_changed', true)
      b2.save
      User.where(:id => u.id).update_all(:updated_at => 2.months.ago)
      expect(u.reload.updated_at).to be < 2.weeks.ago
      Worker.process_queues
      u.reload
      expect(u.reload.updated_at).to be > 2.weeks.ago
    end
    
    it "should touch supervisors of connected users when a sub-board of their home board is modified" do
      u = User.create
      u2 = User.create
      User.link_supervisor_to_user(u2, u)
      b = Board.create(:user => u)
      u.settings['preferences']['home_board'] = {'id' => b.global_id}
      u.save
      b2 = Board.create(:user => u)
      b.settings['buttons'] = [{'id' => 1, 'label' => 'water', 'load_board' => {'id' => b2.global_id}}]
      b.instance_variable_set('@buttons_changed', true)
      b.save
      Worker.process_queues
      Worker.process_queues
      Worker.process_queues
      b2.settings['buttons'] = [{'id' => 1, 'label' => 'wishing'}]
      b2.instance_variable_set('@buttons_changed', true)
      b2.save
      User.where(:id => u2.id).update_all(:updated_at => 2.months.ago)
      expect(u2.reload.updated_at).to be < 2.weeks.ago
      Worker.process_queues
      u.reload
      expect(u2.reload.updated_at).to be > 2.weeks.ago
    end
  end
  
  describe "protected_material?" do
    it "should return the correct value" do
      b = Board.new
      expect(b.protected_material?).to eq(false)
    end
    
    it "should not allow a board to be public if it is unshareable" do
      u = User.create
      b = Board.create(:user => u)
      b.public = true
      expect(b).to receive(:unshareable?).and_return(true)
      b.save
      expect(b.public).to eq(false)
    end

    it "should allow a board to be public if it is not unshareable but has protected material" do
      u = User.create
      b = Board.create(:user => u)
      b.public = true
      expect(b).to receive(:unshareable?).and_return(false)
      b.save
      expect(b.public).to eq(true)
    end
    
    it "should allow demo boards to be public with protected material" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['protected'] = {'demo' => true, 'vocabulary' => true}
      b.public = true
      expect(b.protected_material?).to eq(true)
      b.save
      expect(b.public).to eq(true)
    end
    
    it "should mark board as protected if referencing a protected image" do
      u = User.create
      bi = ButtonImage.create(:settings => {'protected' => true})
      b = Board.create(:user => u)
      expect(b.protected_material?).to eq(false)
      b.process({
        'buttons' => [
          {'id' => 12, 'label' => 'course', 'image_id' => bi.global_id}
        ]
      })
      expect(b.protected_material?).to eq(true)
      expect(b.settings['protected']['media']).to eq(true)
    end

    it "should mark board as protected if referencing a protected sound" do
      u = User.create
      bs = ButtonSound.create(:settings => {'protected' => true})
      b = Board.create(:user => u)
      expect(b.protected_material?).to eq(false)
      b.process({
        'buttons' => [
          {'id' => 12, 'label' => 'course', 'sound_id' => bs.global_id}
        ]
      })
      expect(b.protected_material?).to eq(true)
      expect(b.settings['protected']['media']).to eq(true)
    end
    
    it "should clear a board's protected media status if no protected images or sounds" do
      u = User.create
      bi = ButtonImage.create(:settings => {'protected' => true})
      b = Board.create(:user => u)
      expect(b.protected_material?).to eq(false)
      b.process({
        'buttons' => [
          {'id' => 12, 'label' => 'course', 'image_id' => bi.global_id}
        ]
      })
      expect(b.protected_material?).to eq(true)
      expect(b.settings['protected']['media']).to eq(true)
      b.process({
        'buttons' => [
          {'id' => 12, 'label' => 'course'}
        ]
      })
      expect(b.protected_material?).to eq(false)
      expect(b.settings['protected']['media']).to eq(false)
    end
    
    it "should mark a board as protected when created with protected images" do
      u = User.create
      bi = ButtonImage.create(:settings => {'protected' => true})
      b = Board.process_new({
        'buttons' => [
          {'id' => 12, 'label' => 'course', 'image_id' => bi.global_id}
        ]
      }, {'user' => u})
      expect(b.protected_material?).to eq(true)
      expect(b.settings['protected']['media']).to eq(true)
    end
  end
  
  describe "translate_set" do
    it "should return done if user_id doesn't match" do
      u = User.create
      b = Board.create(:user => u)
      res = b.translate_set({}, 'en', 'es', [b.global_id], true, 'asdf', 1234)
      expect(res).to eq({done: true, translated: false, reason: 'mismatched user'})
    end
    
    it "should do nothing if the board's locale already matches the desired locale" do
      u = User.create
      b = Board.create(:user => u, :settings => {'locale' => 'es'})
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat'},
        {'id' => 2, 'label' => 'cat'}
      ]
      b.save
      res = b.translate_set({'hat' => 'sat', 'cat' => 'rat'}, 'en', 'es', [b.global_id])
      expect(res[:done]).to eq(true)
      expect(b.settings['buttons'][0]['label']).to eq('hat')
    end
    
    it "should translate correct boards" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat'},
        {'id' => 2, 'label' => 'cat'}
      ]
      b.save
      res = b.translate_set({'hat' => 'sat', 'cat' => 'rat'}, 'en', 'es', [b.global_id])
      expect(res[:done]).to eq(true)
      expect(b.settings['buttons'][0]['label']).to eq('sat')
      expect(b.settings['translations']).to eq({
        'default' => 'en',
        'current_label' => 'es',
        'current_vocalization' => 'es',
        '1' => {
          'en' => {'label' => 'hat'},
          'es' => {'label' => 'sat'}
        },
        '2' => {
          'en' => {'label' => 'cat'},
          'es' => {'label' => 'rat'}
        }
      })
    end
    
    it "should keep translations after multiple iterations" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat'},
        {'id' => 2, 'label' => 'cat'}
      ]
      b.save
      res = b.translate_set({'hat' => 'sat', 'cat' => 'rat'}, 'en', 'es', [b.global_id])
      expect(res[:done]).to eq(true)
      expect(b.settings['buttons'][0]['label']).to eq('sat')
      expect(b.settings['translations']).to eq({
        'default' => 'en',
        'current_label' => 'es',
        'current_vocalization' => 'es',
        '1' => {
          'en' => {'label' => 'hat'},
          'es' => {'label' => 'sat'}
        },
        '2' => {
          'en' => {'label' => 'cat'},
          'es' => {'label' => 'rat'}
        }
      })
      
      b.reload
      res = b.translate_set({'sat' => 'yat', 'rat' => 'eat'}, 'es', 'fr', [b.global_id])
      expect(res[:done]).to eq(true)
      expect(b.settings['buttons'][0]['label']).to eq('yat')
      expect(b.settings['translations']).to eq({
        'default' => 'en',
        'current_label' => 'fr',
        'current_vocalization' => 'fr',
        '1' => {
          'en' => {'label' => 'hat'},
          'es' => {'label' => 'sat'},
          'fr' => {'label' => 'yat'}
        },
        '2' => {
          'en' => {'label' => 'cat'},
          'es' => {'label' => 'rat'},
          'fr' => {'label' => 'eat'}
        }
      })
    end

    it "should translate but not switch if specified" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat'},
        {'id' => 2, 'label' => 'cat'}
      ]
      b.save
      res = b.translate_set({'hat' => 'sat', 'cat' => 'rat'}, 'en', 'es', [b.global_id], false)
      expect(res[:done]).to eq(true)
      expect(b.settings['buttons'][0]['label']).to eq('hat')
      expect(b.settings['translations']).to eq({
        'default' => 'en',
        'current_label' => 'en',
        'current_vocalization' => 'en',
        '1' => {
          'en' => {'label' => 'hat'},
          'es' => {'label' => 'sat'}
        },
        '2' => {
          'en' => {'label' => 'cat'},
          'es' => {'label' => 'rat'}
        }
      })
    end
    
    it "should recursively update only the correct boards" do
      u = User.create
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u, :settings => {'locale' => 'es'})
      b3 = Board.create(:user => u)
      b4 = Board.create(:user => u)
      b5 = Board.create(:user => u)
      b1.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}},
        {'id' => 2, 'label' => 'cat', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}},
        {'id' => 2, 'label' => 'rat', 'load_board' => {'id' => b5.global_id, 'key' => b5.key}}
      ]
      b1.save
      b2.settings['buttons'] = [
        {'id' => 1, 'label' => 'fat', 'load_board' => {'id' => b4.global_id, 'key' => b4.key}}
      ]
      b2.save
      b3.settings['buttons'] = [
        {'id' => 1, 'label' => 'cheese', 'vocalization' => 'hat'}
      ]
      b3.save
      b4.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat', 'load_board' => {'id' => b1.global_id, 'key' => b1.key}}
      ]
      b4.save
      b5.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat'}
      ]
      b5.save
      
      res = b1.translate_set({'hat' => 'top', 'cat' => 'feline', 'rat' => 'mouse', 'fat' => 'lard'}, 'en', 'es', [b1.global_id, b2.global_id, b3.global_id, b4.global_id])
      expect(res[:done]).to eq(true)
      expect(b1.reload.settings['buttons'].map{|b| b['label'] }).to eq(['top', 'feline', 'mouse'])
      expect(b2.reload.settings['buttons'].map{|b| b['label'] }).to eq(['fat']) # already translated
      expect(b3.reload.settings['buttons'].map{|b| b['label'] }).to eq(['cheese'])
      expect(b3.reload.settings['buttons'].map{|b| b['vocalization'] }).to eq(['top'])
      expect(b4.reload.settings['buttons'].map{|b| b['label'] }).to eq(['top'])
      expect(b5.reload.settings['buttons'].map{|b| b['label'] }).to eq(['hat'])
    end

    it "should not recurse beyond an unrecognized board" do
      u = User.create
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b3 = Board.create(:user => u)
      b4 = Board.create(:user => u)
      b5 = Board.create(:user => u)
      b1.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}},
        {'id' => 2, 'label' => 'cat', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}},
        {'id' => 2, 'label' => 'rat', 'load_board' => {'id' => b5.global_id, 'key' => b5.key}}
      ]
      b1.save
      b2.settings['buttons'] = [
        {'id' => 1, 'label' => 'fat', 'load_board' => {'id' => b4.global_id, 'key' => b4.key}}
      ]
      b2.save
      b3.settings['buttons'] = [
        {'id' => 1, 'label' => 'cheese', 'vocalization' => 'hat'}
      ]
      b3.save
      b4.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat', 'load_board' => {'id' => b1.global_id, 'key' => b1.key}}
      ]
      b4.save
      b5.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat'}
      ]
      b5.save
      
      res = b1.translate_set({'hat' => 'top', 'cat' => 'feline', 'rat' => 'mouse', 'fat' => 'lard'}, 'en', 'es', [b1.global_id, b3.global_id, b4.global_id])
      expect(res[:done]).to eq(true)
      expect(b1.reload.settings['buttons'].map{|b| b['label'] }).to eq(['top', 'feline', 'mouse'])
      expect(b2.reload.settings['buttons'].map{|b| b['label'] }).to eq(['fat'])
      expect(b3.reload.settings['buttons'].map{|b| b['label'] }).to eq(['cheese'])
      expect(b3.reload.settings['buttons'].map{|b| b['vocalization'] }).to eq(['top'])
      expect(b4.reload.settings['buttons'].map{|b| b['label'] }).to eq(['hat'])
      expect(b5.reload.settings['buttons'].map{|b| b['label'] }).to eq(['hat'])
    end
    
    it "should remember button-level translations" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat'},
        {'id' => 2, 'label' => 'cat'}
      ]
      b.save
      res = b.translate_set({'hat' => 'sat', 'cat' => 'rat'}, 'en', 'es', [b.global_id])
      expect(res[:done]).to eq(true)
      expect(b.settings['buttons'][0]['label']).to eq('sat')
      expect(b.settings['translations']).to eq({
        'default' => 'en',
        'current_label' => 'es',
        'current_vocalization' => 'es',
        '1' => {
          'en' => {
            'label' => 'hat'
          },
          'es' => {
            'label' => 'sat'
          }
        },
        '2' => {
          'en' => {
            'label' => 'cat'
          },
          'es' => {
            'label' => 'rat'
          }
        }
      })
    end

    it "should write a version for any boards that are translated" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat'},
        {'id' => 2, 'label' => 'cat'}
      ]
      b.save
      Worker.process_queues
      Worker.process_queues
      versions = b.reload.versions.count

      b.schedule(:translate_set, {'hat' => 'sat', 'cat' => 'rat'}, 'en', 'es', [b.global_id])
      Worker.process_queues
      expect(b.reload.versions.count).to eq(versions + 1)
    end
  end
  
  describe 'swap_images' do
    it 'should return on an empty library' do
      b = Board.new
      expect(b.swap_images(nil, nil, nil)).to eq({done: true, swapped: false, reason: 'no library specified'})
      expect(b.swap_images('', nil, nil)).to eq({done: true, swapped: false, reason: 'no library specified'})
    end
    
    it 'should return on a mismatched board' do
      b = Board.new
      expect(b.swap_images('arasaac', nil, [], 'asdf')).to eq({done: true, swapped: false, reason: 'mismatched user'})
    end
    
    it 'should call Uploader.find_image for all image buttons' do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hats', 'image_id' => 'whatever'},
        {'id' => 2, 'label' => 'cats', 'image_id' => 'another'}
      ]
      b.save
      expect(Uploader).to receive(:find_images).with('hats', 'bacon', u).and_return([])
      expect(Uploader).to receive(:find_images).with('cats', 'bacon', u).and_return([{
        'url' => 'http://www.example.com/pic.png',
        'content_type' => 'image/png'
      }])
      res = b.swap_images('bacon', u, [])
      expect(res).to eq({done: true, library: 'bacon', board_ids: [], updated: [b.global_id], visited: [b.global_id]})
    end
    
    it 'should create and set button images for changed images, including creating board_button_image connections' do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hats', 'image_id' => 'whatever'},
        {'id' => 2, 'label' => 'cats', 'image_id' => 'another'}
      ]
      b.save
      expect(Uploader).to receive(:find_images).with('hats', 'bacon', u).and_return([])
      expect(Uploader).to receive(:find_images).with('cats', 'bacon', u).and_return([{
        'url' => 'http://www.example.com/pic.png',
        'content_type' => 'image/png'
      }])
      res = b.swap_images('bacon', u, [])
      expect(res).to eq({done: true, library: 'bacon', board_ids: [], updated: [b.global_id], visited: [b.global_id]})
      img = ButtonImage.last
      expect(b.reload.button_images.to_a).to eq([img])
      expect(b.settings['buttons']).to eq([
        {'id' => 1, 'label' => 'hats', 'image_id' => 'whatever'},
        {'id' => 2, 'label' => 'cats', 'image_id' => img.global_id}
      ])
    end
    
    it 'should do nothing when no images found' do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hats', 'image_id' => 'whatever'},
        {'id' => 2, 'label' => 'cats', 'image_id' => 'another'}
      ]
      b.save
      expect(b).to_not receive(:save)
      expect(Uploader).to receive(:find_images).with('hats', 'bacon', u).and_return([])
      expect(Uploader).to receive(:find_images).with('cats', 'bacon', u).and_return([])
      res = b.swap_images('bacon', u, [])
      expect(res).to eq({done: true, library: 'bacon', board_ids: [], updated: [b.global_id], visited: [b.global_id]})
    end

    it 'should do nothing when asking for premium images but not enabled' do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hats', 'image_id' => 'whatever'},
        {'id' => 2, 'label' => 'cats', 'image_id' => 'another'}
      ]
      b.save
      res = b.swap_images('pcs', u, [])
      expect(res).to eq({done: true, swapped: false, reason: "not authorized to access premium library"})
    end

    it 'should look up default images for a quicker lookup process' do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hats', 'image_id' => 'whatever'},
        {'id' => 2, 'label' => 'cats', 'image_id' => 'another'}
      ]
      b.save
      expect(Uploader).to receive(:default_images).with('bacon', ['hats', 'cats'], 'en', u).and_return({
        'cats' => {
          'url' => 'http://www.example.com/pic.png',
          'content_type' => 'image/png'
        }
      })
      expect(Uploader).to receive(:find_images).with('hats', 'bacon', u).and_return([])
      expect(Uploader).to_not receive(:find_images).with('cats', 'bacon', u)
      res = b.swap_images('bacon', u, [])
      expect(res).to eq({done: true, library: 'bacon', board_ids: [], updated: [b.global_id], visited: [b.global_id]})
    end

    it 'should skip keyboard boards if specified' do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.create(:user => u, :key => "#{u.user_name}/keyboard")
      b3 = Board.create(:user => u)
      b.process({'buttons' => [
        {'id' => 1, 'label' => 'cats', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}}
      ]}, {user: u})
      b2.process({'buttons' => [
        {'id' => 2, 'label' => 'hats', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
      ]}, {user: u})
      b3.process({'buttons' => [
        {'id' => 3, 'label' => 'flats'}
      ]}, {user: u})
      Worker.process_queues
      expect(b.reload.settings['downstream_board_ids']).to eq([b2.global_id, b3.global_id])
      expect(b2.reload.settings['downstream_board_ids']).to eq([b3.global_id])
      
      expect(Uploader).to_not receive(:find_images).with('hats', 'bacon', u)
      expect(Uploader).to receive(:find_images).with('cats', 'bacon', u).and_return([{
        'url' => 'http://www.example.com/cat.png', 'content_type' => 'image/png'
      }])
      expect(Uploader).to_not receive(:find_images).with('flats', 'bacon', u)
      list = [b.global_id, b2.global_id, b3.global_id]
      list.instance_variable_set('@skip_keyboard', true)
      res = b.swap_images('bacon', u, list)
    end
    
    it 'should not error on buttons with no images' do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hats'},
        {'id' => 2, 'label' => 'cats'}
      ]
      b.save
      expect(Uploader).to receive(:find_images).with('hats', 'bacon', u).and_return([])
      expect(Uploader).to receive(:find_images).with('cats', 'bacon', u).and_return([{
        'url' => 'http://www.example.com/pic.png',
        'content_type' => 'image/png'
      }])
      res = b.swap_images('bacon', u, [])
      expect(res).to eq({done: true, library: 'bacon', board_ids: [], updated: [b.global_id], visited: [b.global_id]})
      img = ButtonImage.last
      expect(b.settings['buttons']).to eq([
        {'id' => 1, 'label' => 'hats'},
        {'id' => 2, 'label' => 'cats', 'image_id' => img.global_id}
      ])
    end
    
    it 'should recursively find boards' do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b3 = Board.create(:user => u)
      b.process({'buttons' => [
        {'id' => 1, 'label' => 'cats', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}}
      ]}, {user: u})
      b2.process({'buttons' => [
        {'id' => 2, 'label' => 'hats', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
      ]}, {user: u})
      b3.process({'buttons' => [
        {'id' => 3, 'label' => 'flats'}
      ]}, {user: u})
      Worker.process_queues
      expect(b.reload.settings['downstream_board_ids']).to eq([b2.global_id, b3.global_id])
      expect(b2.reload.settings['downstream_board_ids']).to eq([b3.global_id])
      
      expect(Uploader).to receive(:find_images).with('hats', 'bacon', u).and_return([{
        'url' => 'http://www.example.com/hat.png', 'content_type' => 'image/png'
      }])
      expect(Uploader).to receive(:find_images).with('cats', 'bacon', u).and_return([{
        'url' => 'http://www.example.com/cat.png', 'content_type' => 'image/png'
      }])
      expect(Uploader).to_not receive(:find_images).with('flats', 'bacon', u)
      res = b.swap_images('bacon', u, [b.global_id, b2.global_id])
      bis = b.reload.button_images
      expect(bis.count).to eq(1)
      bi = bis[0]
      bis2 = b2.reload.button_images
      expect(bis2.count).to eq(1)
      bi2 = bis2[0]
      bis3 = b3.reload.button_images
      expect(bis3.count).to eq(0)
      expect(res).to eq({done: true, library: 'bacon', board_ids: [b.global_id, b2.global_id], updated: [b.global_id, b2.global_id], visited: [b.global_id, b2.global_id, b3.global_id]})
      expect(b.reload.settings['buttons']).to eq([
        {'id' => 1, 'label' => 'cats', 'image_id' => bi.global_id, 'load_board' => {'id' => b2.global_id, 'key' => b2.key}}
      ])
      expect(b2.reload.settings['buttons']).to eq([
        {'id' => 2, 'label' => 'hats', 'image_id' => bi2.global_id, 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
      ])
      expect(b3.reload.settings['buttons']).to eq([
        {'id' => 3, 'label' => 'flats', 'part_of_speech' => 'noun', 'suggested_part_of_speech' => 'noun'}
      ])
    end
    
    it 'should stop when the user no longer matches' do
      u = User.create
      u2 = User.create
      b = Board.create(:user => u)
      b2 = Board.create(:user => u2)
      b3 = Board.create(:user => u)
      b.process({'buttons' => [
        {'id' => 1, 'label' => 'cats', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}}
      ]}, {user: u2})
      b2.process({'buttons' => [
        {'id' => 2, 'label' => 'hats', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
      ]}, {user: u})
      b3.process({'buttons' => [
        {'id' => 3, 'label' => 'flats'}
      ]}, {user: u})
      Worker.process_queues
      expect(b.reload.settings['downstream_board_ids']).to eq([b2.global_id, b3.global_id])
      expect(b2.reload.settings['downstream_board_ids']).to eq([b3.global_id])
      
      expect(Uploader).to_not receive(:find_images).with('hats', 'bacon', u)
      expect(Uploader).to receive(:find_images).with('cats', 'bacon', u).and_return([{
        'url' => 'http://www.example.com/cat.png', 'content_type' => 'image/png'
      }])
      expect(Uploader).to_not receive(:find_images).with('flats', 'bacon', u)
      res = b.swap_images('bacon', u, [b.global_id, b2.global_id, b3.global_id])
      bis = b.reload.button_images
      expect(bis.count).to eq(1)
      bi = bis[0]
      bis2 = b2.reload.button_images
      expect(bis2.count).to eq(0)
      bis3 = b3.reload.button_images
      expect(bis3.count).to eq(0)
      expect(res).to eq({done: true, library: 'bacon', board_ids: [b.global_id, b2.global_id, b3.global_id], updated: [b.global_id], visited: [b.global_id, b2.global_id]})
      expect(b.reload.settings['buttons']).to eq([
        {'id' => 1, 'label' => 'cats', 'image_id' => bi.global_id, 'load_board' => {'id' => b2.global_id, 'key' => b2.key}}
      ])
      expect(b2.reload.settings['buttons']).to eq([
        {'id' => 2, 'label' => 'hats', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
      ])
      expect(b3.reload.settings['buttons']).to eq([
        {'id' => 3, 'label' => 'flats', 'part_of_speech' => 'noun', 'suggested_part_of_speech' => 'noun'}
      ])
    end
    
    it 'should only find boards it can access' do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b3 = Board.create(:user => u)
      b.process({'buttons' => [
        {'id' => 1, 'label' => 'cats', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}}
      ]}, {user: u})
      b2.process({'buttons' => [
        {'id' => 2, 'label' => 'hats', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
      ]}, {user: u})
      b3.process({'buttons' => [
        {'id' => 3, 'label' => 'flats'}
      ]}, {user: u})
      Worker.process_queues
      expect(b.reload.settings['downstream_board_ids']).to eq([b2.global_id, b3.global_id])
      expect(b2.reload.settings['downstream_board_ids']).to eq([b3.global_id])
      
      expect(Uploader).to_not receive(:find_images).with('hats', 'bacon', u)
      expect(Uploader).to receive(:find_images).with('cats', 'bacon', u).and_return([{
        'url' => 'http://www.example.com/cat.png', 'content_type' => 'image/png'
      }])
      expect(Uploader).to_not receive(:find_images).with('flats', 'bacon', u)
      res = b.swap_images('bacon', u, [b.global_id, b3.global_id])
      bis = b.reload.button_images
      expect(bis.count).to eq(1)
      bi = bis[0]
      bis2 = b2.reload.button_images
      expect(bis2.count).to eq(0)
      bis3 = b3.reload.button_images
      expect(bis3.count).to eq(0)
      expect(res).to eq({done: true, library: 'bacon', board_ids: [b.global_id, b3.global_id], updated: [b.global_id], visited: [b.global_id, b2.global_id]})
      expect(b.reload.settings['buttons']).to eq([
        {'id' => 1, 'label' => 'cats', 'image_id' => bi.global_id, 'load_board' => {'id' => b2.global_id, 'key' => b2.key}}
      ])
      expect(b2.reload.settings['buttons']).to eq([
        {'id' => 2, 'label' => 'hats', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
      ])
      expect(b3.reload.settings['buttons']).to eq([
        {'id' => 3, 'label' => 'flats', 'part_of_speech' => 'noun', 'suggested_part_of_speech' => 'noun'}
      ])
    end

    it "should add a version for any boards with images swapped" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hats', 'image_id' => 'whatever'},
        {'id' => 2, 'label' => 'cats', 'image_id' => 'another'}
      ]
      b.save
      expect(Uploader).to receive(:find_images).with('hats', 'bacon', u).and_return([])
      expect(Uploader).to receive(:find_images).with('cats', 'bacon', u).and_return([{
        'url' => 'http://www.example.com/pic.png',
        'content_type' => 'image/png'
      }])
      Worker.process_queues
      Worker.process_queues
      versions = b.versions.count

      b.schedule(:swap_images, 'bacon', u.global_id, [])
      Worker.process_queues
      expect(b.versions.count).to eq(versions + 1)
      img = ButtonImage.last
      expect(b.reload.button_images.to_a).to eq([img])
      expect(b.settings['buttons']).to eq([
        {'id' => 1, 'label' => 'hats', 'image_id' => 'whatever'},
        {'id' => 2, 'label' => 'cats', 'image_id' => img.global_id}
      ])
    end
  end
  
  describe "process_button" do
    it "should update the button if found" do
      u = User.create
      b = Board.create(:user => u, :settings => {
        'buttons' => [
          {'id' => '123'}, {'id' => '234'}
        ]
      })
      b.process_button({
        'id' => '234',
        'sound_id' => '12345'
      })
      expect(b.reload.settings['buttons']).to eq([
        {'id' => '123'}, {'id' => '234', 'sound_id' => '12345'}
      ])
    end 
    
    it "should schedule a button set update" do
      u = User.create
      b = Board.create(:user => u, :settings => {
        'buttons' => [
          {'id' => '123'}, {'id' => '234'}
        ]
      })
      b.process_button({
        'id' => '234',
        'sound_id' => '12345'
      })
      expect(b.reload.settings['buttons']).to eq([
        {'id' => '123'}, {'id' => '234', 'sound_id' => '12345'}
      ])
      expect(Worker.scheduled?(Board, :perform_action, {:id => b.id, :method => 'update_button_sets', :arguments => []})).to eq(true)
    end
    
    it "should align the button to the sound record" do
      u = User.create
      s = ButtonSound.create(:user => u)
      b = Board.create(:user => u, :settings => {
        'buttons' => [
          {'id' => '123'}, {'id' => '234'}
        ]
      })
      b.process_button({
        'id' => '234',
        'sound_id' => s.global_id
      })
      expect(b.reload.settings['buttons']).to eq([
        {'id' => '123'}, {'id' => '234', 'sound_id' => s.global_id}
      ])
      expect(b.button_sounds).to eq([s])
    end
  end
  
  describe "update_button_sets" do
    it "should schedule updates for all upstream button sets" do
      u = User.create
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u, :settings => {
        'immediately_upstream_board_ids' => [b1.global_id]
      })
      b3 = Board.create(:user => u, :settings => {
        'immediately_upstream_board_ids' => [b2.global_id]
      })
      b2.settings['immediately_upstream_board_ids'] = [b1.global_id, b3.global_id]
      b2.save
      b3.update_button_sets
      expect(Worker.scheduled?(BoardDownstreamButtonSet, :perform_action, {:method => 'update_for', :arguments => [b1.global_id]})).to eq(true)
      expect(Worker.scheduled?(BoardDownstreamButtonSet, :perform_action, {:method => 'update_for', :arguments => [b2.global_id]})).to eq(true)
      expect(Worker.scheduled?(BoardDownstreamButtonSet, :perform_action, {:method => 'update_for', :arguments => [b3.global_id]})).to eq(true)
    end
  end
end
