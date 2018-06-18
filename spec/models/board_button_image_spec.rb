require 'spec_helper'

describe BoardButtonImage, :type => :model do
  describe "images_for_board" do
    it "should return all button_images connected to a specific board" do
      i = ButtonImage.create
      bi = BoardButtonImage.create(:board_id => 1, :button_image_id => i.id)
      expect(BoardButtonImage.images_for_board(1).to_a).to eq([i])
    end
  end
  
  describe "connect" do
    it "create connections for all found refs" do
      u = User.create
      b = Board.create(:user => u)
      i = ButtonImage.create
      i2 = ButtonImage.create
      BoardButtonImage.connect(b.id, [{:id => i.global_id}, {:id => i2.id + 3}])
      expect(BoardButtonImage.count).to eq(1)
      bi = BoardButtonImage.last
      expect(bi.button_image).to eq(i)
    end
    
    it "should track use for images when user_id is provided" do
      u = User.create
      b = Board.create(:user => u)
      i = ButtonImage.create
      expect(ButtonImage).to receive(:track_image_use).with({
        'label' => "hat",
        'external_id' => nil,
        'locale' => 'en',
        'user_id' => 1234
      })
      BoardButtonImage.connect(b.id, [{:id => i.global_id, :label => "hat"}], :user_id => 1234)
      Worker.process_queues      
      expect(BoardButtonImage.count).to eq(1)
      bi = BoardButtonImage.last
      expect(bi.button_image).to eq(i)
    end
  end
  
  describe "disconnect" do
    it "should delete connections for all found refs" do
      u = User.create
      b = Board.create(:user => u)
      i = ButtonImage.create
      i2 = ButtonImage.create
      BoardButtonImage.connect(b.id, [{:id => i.global_id}, {:id => i2.global_id}])
      expect(BoardButtonImage.count).to eq(2)
      BoardButtonImage.disconnect(b.id, [{:id => i.global_id}, {:id => i2.id + 3}])
      expect(BoardButtonImage.count).to eq(1)
    end
  end
  
  describe "board.map_images" do
    it "should do nothing unless button has changed" do
      b = Board.new
      expect(b.map_images).to eq(nil)
    end
    
    it "should disconnect orphaned records and connect new buttons" do
      u = User.create
      b = Board.create(:user => u)
      i = ButtonImage.create
      i2 = ButtonImage.create
      i3 = ButtonImage.create
      BoardButtonImage.create(:board_id => b.id, :button_image_id => i.id)
      expect(BoardButtonImage.count).to eq(1)
      expect(BoardButtonImage.all.map(&:button_image_id)).to eq([i.id])
      b.settings['buttons'] = [
        {'image_id' => i2.global_id},
        {'image_id' => i3.global_id}
      ]
      b.instance_variable_set('@buttons_changed', true)
      b.map_images
      expect(BoardButtonImage.count).to eq(2)
      expect(BoardButtonImage.all.map(&:button_image_id).sort).to eq([i2.id, i3.id].sort)
    end
  end
end
