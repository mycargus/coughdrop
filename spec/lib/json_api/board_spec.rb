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
