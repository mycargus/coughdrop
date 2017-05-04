require 'spec_helper'

describe JsonApi::Board do
  it "should have defined pagination defaults" do
    expect(JsonApi::Board::TYPE_KEY).to eq('board')
    expect(JsonApi::Board::DEFAULT_PAGE).to eq(25)
    expect(JsonApi::Board::MAX_PAGE).to eq(50)
  end

  describe "build_json" do
    it "should not include unlisted settings" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['hat'] = 'black'
      expect(JsonApi::Board.build_json(b).keys).not_to be_include('hat')
    end
    
    it "should return appropriate attributes" do
      u = User.create
      b = Board.create(:user => u)
      ['id', 'key', 'public', 'user_name'].each do |key|
        expect(JsonApi::Board.build_json(b).keys).to be_include(key)
      end
    end
    
    it "should include permissions and stars if permissions are requested" do
      u = User.create
      b = Board.create(:user => u)
      expect(JsonApi::Board.build_json(b, :permissions => u)['permissions']).to eq({'user_id' => u.global_id, 'view' => true, 'edit' => true, 'delete' => true, 'share' => true})
      expect(JsonApi::Board.build_json(b, :permissions => u)['starred']).to eq(false)
    end
    
    it "should include translations if defined" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['translations'] = {'a' => 1}
      expect(JsonApi::Board.as_json(b, :permissions => u, :wrapper => true)['board']['translations']).to eq({'a' => 1})
    end
  end
  
  describe "extra_includes" do
    it "should include linked images and sounds" do
      u = User.create
      b = Board.create(:user => u)
      hash = JsonApi::Board.extra_includes(b, {})
      expect(hash['images']).to eq([])
      expect(hash['sounds']).to eq([])
      
      hash = JsonApi::Board.as_json(b, :wrapper => true)
      expect(hash['images']).to eq([])
      expect(hash['sounds']).to eq([])
      
      i = ButtonImage.create
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'parasol', 'image_id' => i.global_id}
      ]
      b.instance_variable_set('@buttons_changed', true)
      b.save
      expect(b.button_images.count).to eq(1)
      
      hash = JsonApi::Board.as_json(b.reload, :wrapper => true)
      expect(hash['images'].length).to eq(1)
      expect(hash['images'][0]['id']).to eq(i.global_id)
      expect(hash['sounds']).to eq([])
    end
    
    it "should include image and sound url hashes" do
      u = User.create
      b = Board.create(:user => u)
      hash = JsonApi::Board.extra_includes(b, {})
      expect(hash['images']).to eq([])
      expect(hash['sounds']).to eq([])
      
      hash = JsonApi::Board.as_json(b, :wrapper => true)
      expect(hash['images']).to eq([])
      expect(hash['sounds']).to eq([])
      
      i = ButtonImage.create(url: 'http://www.example.com/pic.png')
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'parasol', 'image_id' => i.global_id}
      ]
      b.instance_variable_set('@buttons_changed', true)
      b.save
      expect(b.button_images.count).to eq(1)
      
      hash = JsonApi::Board.as_json(b.reload, :wrapper => true)
      img = {}
      img[i.global_id] = 'http://www.example.com/pic.png'
      expect(hash['board']['image_urls']).to eq(img)
      expect(hash['board']['sound_urls']).to eq({})
    end
    
    it "should include cached image urls" do
      bi1 = ButtonImage.create(:url => "bacon:1", :settings => {'cached_copy_url' => 'http://www.example.com/bacon/cache/1'})
      bi2 = ButtonImage.create(:url => "bacon:2", :settings => {'cached_copy_url' => 'http://www.example.com/bacon/cache/2'})
      bbi1 = ButtonImage.create(:url => 'http://www.example.com/bacon/1')
      bbi2 = ButtonImage.create(:url => 'http://www.example.com/bacon/1')
      bbi3 = ButtonImage.create(:url => 'http://www.example.com/bacon/2')
      bbi4 = ButtonImage.create(:url => 'http://www.example.com/bacon/3')
      bbi5 = ButtonImage.create(:url => 'http://www.example.com/bacon/4')
      u = User.create
      expect(Uploader).to receive(:lessonpix_credentials).with(u).and_return({})
      expect(ButtonImage).to receive(:cached_copy_identifiers).with('http://www.example.com/bacon/1').and_return({
        user_id: 'sam',
        library: 'lessonpix',
        image_id: '123',
        url: 'bacon:1'
      }).exactly(2).times
      expect(ButtonImage).to receive(:cached_copy_identifiers).with('http://www.example.com/bacon/2').and_return({
        user_id: 'sam',
        library: 'lessonpix',
        image_id: '123',
        url: 'bacon:2'
      })
      expect(ButtonImage).to receive(:cached_copy_identifiers).with('http://www.example.com/bacon/3').and_return({
        user_id: 'sam',
        library: 'lessonpix',
        image_id: '123',
        url: 'bacon:3'
      })
      expect(Uploader).to receive(:protected_remote_url?).and_return(true).exactly(7).times
      expect(ButtonImage).to receive(:cached_copy_identifiers).with('http://www.example.com/bacon/4').and_return(nil)
      expect(Uploader).to receive(:fallback_image_url).and_return("http://www.example.com/bacon/cache/fallback").exactly(4).times
      
      b = Board.create(:user => u)
      b.instance_variable_set('@buttons_changed', true)
      b.settings['buttons'] = [
        {'id' => 1, 'image_id' => bbi1.global_id, 'label' => 'a'},
        {'id' => 2, 'image_id' => bbi2.global_id, 'label' => 'b'},
        {'id' => 3, 'image_id' => bbi3.global_id, 'label' => 'c'},
        {'id' => 4, 'image_id' => bbi4.global_id, 'label' => 'd'},
        {'id' => 5, 'image_id' => bbi5.global_id, 'label' => 'e'},
      ]
      b.save
      
      hash = JsonApi::Board.as_json(b.reload, :permissions => u, :wrapper => true)
      expect(hash['images'].length).to eq(5)
      images = hash['images'].sort_by{|i| i['id'] }
      expect(images[0]['id']).to eq(bbi1.global_id)
      expect(images[0]['url']).to eq('http://www.example.com/bacon/cache/1')
      expect(images[1]['id']).to eq(bbi2.global_id)
      expect(images[1]['url']).to eq('http://www.example.com/bacon/cache/1')
      expect(images[2]['id']).to eq(bbi3.global_id)
      expect(images[2]['url']).to eq('http://www.example.com/bacon/cache/2')
      expect(images[3]['id']).to eq(bbi4.global_id)
      expect(images[3]['url']).to eq('http://www.example.com/bacon/3')
      expect(images[4]['id']).to eq(bbi5.global_id)
      expect(images[4]['url']).to eq('http://www.example.com/bacon/4')
    end

    it "should include cached fallback urls" do
      bi1 = ButtonImage.create(:url => "bacon:1", :settings => {'cached_copy_url' => 'http://www.example.com/bacon/cache/1'})
      bi2 = ButtonImage.create(:url => "bacon:2", :settings => {'cached_copy_url' => 'http://www.example.com/bacon/cache/2'})
      bbi1 = ButtonImage.create(:url => 'http://www.example.com/bacon/1')
      bbi2 = ButtonImage.create(:url => 'http://www.example.com/bacon/1')
      bbi3 = ButtonImage.create(:url => 'http://www.example.com/bacon/2')
      bbi4 = ButtonImage.create(:url => 'http://www.example.com/bacon/3')
      bbi5 = ButtonImage.create(:url => 'http://www.example.com/bacon/4')
      u = User.create
      expect(Uploader).to receive(:lessonpix_credentials).with(u).and_return(nil)
      expect(ButtonImage).to receive(:cached_copy_identifiers).with('http://www.example.com/bacon/1').and_return({
        user_id: 'sam',
        library: 'lessonpix',
        image_id: '123',
        url: 'bacon:1'
      }).exactly(2).times
      expect(ButtonImage).to receive(:cached_copy_identifiers).with('http://www.example.com/bacon/2').and_return({
        user_id: 'sam',
        library: 'lessonpix',
        image_id: '123',
        url: 'bacon:2'
      })
      expect(ButtonImage).to receive(:cached_copy_identifiers).with('http://www.example.com/bacon/3').and_return({
        user_id: 'sam',
        library: 'lessonpix',
        image_id: '123',
        url: 'bacon:3'
      })
      expect(Uploader).to receive(:protected_remote_url?).and_return(true).exactly(4).times
      expect(ButtonImage).to receive(:cached_copy_identifiers).with('http://www.example.com/bacon/4').and_return(nil)
      expect(Uploader).to receive(:fallback_image_url).and_return("http://www.example.com/bacon/cache/fallback").exactly(4).times
      
      b = Board.create(:user => u)
      b.instance_variable_set('@buttons_changed', true)
      b.settings['buttons'] = [
        {'id' => 1, 'image_id' => bbi1.global_id, 'label' => 'a'},
        {'id' => 2, 'image_id' => bbi2.global_id, 'label' => 'b'},
        {'id' => 3, 'image_id' => bbi3.global_id, 'label' => 'c'},
        {'id' => 4, 'image_id' => bbi4.global_id, 'label' => 'd'},
        {'id' => 5, 'image_id' => bbi5.global_id, 'label' => 'e'},
      ]
      b.save
      
      hash = JsonApi::Board.as_json(b.reload, :permissions => u, :wrapper => true)
      expect(hash['images'].length).to eq(5)
      images = hash['images'].sort_by{|i| i['id'] }
      expect(images[0]['id']).to eq(bbi1.global_id)
      expect(images[0]['url']).to eq('http://www.example.com/bacon/1')
      expect(images[1]['id']).to eq(bbi2.global_id)
      expect(images[1]['url']).to eq('http://www.example.com/bacon/1')
      expect(images[2]['id']).to eq(bbi3.global_id)
      expect(images[2]['url']).to eq('http://www.example.com/bacon/2')
      expect(images[3]['id']).to eq(bbi4.global_id)
      expect(images[3]['url']).to eq('http://www.example.com/bacon/3')
      expect(images[4]['id']).to eq(bbi5.global_id)
      expect(images[4]['url']).to eq('http://www.example.com/bacon/4')
    end
    
    it "should include copy information if any for the current user" do
      u = User.create
      b = Board.create(:user => u)
      u2 = User.create
      
      hash = JsonApi::Board.as_json(b, :permissions => u2, :wrapper => true)
      expect(hash['board']['copy']).to eq(nil)
      
      b2 = Board.create(:user => u2, :parent_board_id => b.id)
      hash = JsonApi::Board.as_json(b, :permissions => u2, :wrapper => true)
      expect(hash['board']['copy']).to eq({
        'id' => b2.global_id,
        'key' => b2.key
      })
      expect(hash['board']['copies']).to eq(1)
    end
    
    it "should include original-board information if any for the current board" do
      u = User.create
      b = Board.create(:user => u)
      u2 = User.create
      
      hash = JsonApi::Board.as_json(b, :permissions => u2, :wrapper => true)
      expect(hash['board']['copy']).to eq(nil)
      
      b2 = Board.create(:user => u2, :parent_board_id => b.id)
      hash = JsonApi::Board.as_json(b2, :permissions => u2, :wrapper => true)
      expect(hash['board']['original']).to eq({
        'id' => b.global_id,
        'key' => b.key
      })
    end

    it "should not include copy information if there are copies, but only by supervisees" do
      u = User.create
      b = Board.create(:user => u)
      u2 = User.create
      u3 = User.create
      User.link_supervisor_to_user(u3, u2)
      Worker.process_queues
      
      hash = JsonApi::Board.as_json(b, :permissions => u2, :wrapper => true)
      expect(hash['board']['copy']).to eq(nil)
      
      b2 = Board.create(:user => u2, :parent_board_id => b.id)
      expect(b.find_copies_by(u3).length).to eq(1)
      hash = JsonApi::Board.as_json(b, :permissions => u3, :wrapper => true)
      expect(hash['board']['copy']).to eq(nil)
      expect(hash['board']['copies']).to eq(1)
    end

    it "should count copy information from supervisees" do
      u = User.create
      b = Board.create(:user => u)
      u2 = User.create
      u3 = User.create
      User.link_supervisor_to_user(u3, u2)
      Worker.process_queues
      
      hash = JsonApi::Board.as_json(b, :permissions => u2, :wrapper => true)
      expect(hash['board']['copy']).to eq(nil)
      
      b2 = Board.create(:user => u2, :parent_board_id => b.id)
      b3 = Board.create(:user => u3, :parent_board_id => b.id)
      hash = JsonApi::Board.as_json(b, :permissions => u3, :wrapper => true)
      expect(hash['board']['copy']).to eq({
        'id' => b3.global_id,
        'key' => b3.key
      })
      expect(hash['board']['copies']).to eq(2)
    end
  end
end
