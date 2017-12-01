require 'spec_helper'

describe Flusher do
  describe "find_user" do
    it "should error on user not found" do
      expect { Flusher.find_user(0, 'nobody') }.to raise_error("user not found")
    end
    
    it "should error on mismatched user" do
      u = User.create
      expect { Flusher.find_user(u.global_id, 'wrong_name') }.to raise_error("wrong user!")
    end
    
    it "should return the user if found" do
      u = User.create
      expect(Flusher.find_user(u.global_id, u.user_name)).to eq(u)
    end
  end
  
  describe "flush_versions" do
    it "should delete all versions", :versioning => true do
      PaperTrail.whodunnit = 'user:sue'
      u = User.create
      u.user_name = 'different_name'
      u.save
      u.user_name = 'another_name'
      u.save
      u.reload
      expect(u.versions.count).to eq(3)
      Flusher.flush_versions(u.id, u.class.to_s)
      u.reload
      expect(u.versions.count).to eq(0)
    end
  end
  
  describe "flush_record" do
    it "should destroy the record" do
      u = User.create
      expect(User.where(:id => u.id).count).to eq(1)
      Flusher.flush_record(u)
      expect(User.where(:id => u.id).count).to eq(0)
    end
    
    it "should call flush_versions" do
      u = User.create
      expect(Flusher).to receive(:flush_versions).with(u.id, u.class.to_s)
      Flusher.flush_record(u)
    end
  end
  
  describe "flush_user_logs" do
    it "should call find_user" do
      u = User.create
      expect(Flusher).to receive(:find_user).with(u.global_id, u.user_name).and_return(u)
      Flusher.flush_user_logs(u.global_id, u.user_name)
    end
    
    it "should remove all log sessions and log session versions", :versioning => true do
      PaperTrail.whodunnit = 'user:jane'
      u = User.create
      d = Device.create(:user => u)
      s = LogSession.new(:device => d, :user => u, :author => u)
      s.data = {}
      s.data['events'] = [
        {'user_id' => u.global_id, 'geo' => ['2', '3'], 'timestamp' => 10.minutes.ago.to_i, 'type' => 'button', 'button' => {'label' => 'hat', 'board' => {'id' => '1_1'}}},
        {'user_id' => u.global_id, 'geo' => ['1', '2'], 'timestamp' => 8.minutes.ago.to_i, 'type' => 'button', 'button' => {'label' => 'cow', 'board' => {'id' => '1_1'}}}
      ]
      s.save
      s2 = LogSession.new(:device => d, :user => u, :author => u)
      s2.data = {}
      s2.data['events'] = [
        {'user_id' => u.global_id, 'geo' => ['2', '3'], 'timestamp' => 90.minutes.ago.to_i, 'type' => 'button', 'button' => {'label' => 'hat', 'board' => {'id' => '1_1'}}},
        {'user_id' => u.global_id, 'geo' => ['1', '2'], 'timestamp' => 94.minutes.ago.to_i, 'type' => 'button', 'button' => {'label' => 'cow', 'board' => {'id' => '1_1'}}}
      ]
      s2.save
      
      Flusher.flush_user_logs(u.global_id, u.user_name)
      expect(LogSession.where(:id => s.id).count).to eq(0)
      expect(PaperTrail::Version.where(:item_type => 'LogSession', :item_id => s.id).count).to eq(0)
      expect(PaperTrail::Version.where(:item_type => 'LogSession').count).to eq(0)
      expect(LogSession.where(:id => s2.id).count).to eq(0)
      expect(PaperTrail::Version.where(:item_type => 'LogSession', :item_id => s2.id).count).to eq(0)
    end
    
    it "should remove weekly stats summaries" do
      PaperTrail.whodunnit = 'user:jane'
      u = User.create
      d = Device.create(:user => u)
      s = LogSession.new(:device => d, :user => u, :author => u)
      s.data = {}
      s.data['events'] = [
        {'user_id' => u.global_id, 'geo' => ['2', '3'], 'timestamp' => 10.minutes.ago.to_i, 'type' => 'button', 'button' => {'label' => 'hat', 'board' => {'id' => '1_1'}}},
        {'user_id' => u.global_id, 'geo' => ['1', '2'], 'timestamp' => 8.minutes.ago.to_i, 'type' => 'button', 'button' => {'label' => 'cow', 'board' => {'id' => '1_1'}}}
      ]
      s.save
      s2 = LogSession.new(:device => d, :user => u, :author => u)
      s2.data = {}
      s2.data['events'] = [
        {'user_id' => u.global_id, 'geo' => ['2', '3'], 'timestamp' => 90.minutes.ago.to_i, 'type' => 'button', 'button' => {'label' => 'hat', 'board' => {'id' => '1_1'}}},
        {'user_id' => u.global_id, 'geo' => ['1', '2'], 'timestamp' => 94.minutes.ago.to_i, 'type' => 'button', 'button' => {'label' => 'cow', 'board' => {'id' => '1_1'}}}
      ]
      s2.save
      Worker.process_queues
      expect(WeeklyStatsSummary.where(user_id: u.id).count).to eq(1)
      
      Flusher.flush_user_logs(u.global_id, u.user_name)
      expect(LogSession.where(:id => s.id).count).to eq(0)
      expect(PaperTrail::Version.where(:item_type => 'LogSession', :item_id => s.id).count).to eq(0)
      expect(PaperTrail::Version.where(:item_type => 'LogSession').count).to eq(0)
      expect(LogSession.where(:id => s2.id).count).to eq(0)
      expect(PaperTrail::Version.where(:item_type => 'LogSession', :item_id => s2.id).count).to eq(0)
      expect(WeeklyStatsSummary.where(user_id: u.id).count).to eq(0)
    end
  end
  
  describe "flush_board" do
    it "should call flush_record" do
      u = User.create
      b = Board.create(:user => u)
      expect(Flusher).to receive(:flush_record).with(b, b.id, b.class.to_s)
      Flusher.flush_board(b.global_id, b.key)
    end
    
    it "should remove the board's image and sound records", :versioning => true do
      PaperTrail.whodunnit = 'user:todd'
      u = User.create
      b = Board.create(:user => u)
      i = ButtonImage.create
      i2 = ButtonImage.create
      BoardButtonImage.connect(b.id, [{:id => i.global_id}, {:id => i2.global_id}])
      s = ButtonSound.create
      BoardButtonSound.create(:board_id => b.id, :button_sound_id => s.id)
      expect(ButtonImage.count).to eq(2)
      expect(ButtonSound.count).to eq(1)

      Flusher.flush_board(b.global_id, b.key)
      expect(ButtonImage.count).to eq(0)
      expect(ButtonSound.count).to eq(0)
      expect(BoardButtonImage.where(:board_id => b.id).count).to eq(0)
      expect(BoardButtonSound.where(:board_id => b.id).count).to eq(0)
      expect(Board.where(:id => b.id).count).to eq(0)
      expect(PaperTrail::Version.where(:item_type => 'ButtonImage', :item_id => i.id).count).to eq(0)
      expect(PaperTrail::Version.where(:item_type => 'ButtonImage', :item_id => i2.id).count).to eq(0)
      expect(PaperTrail::Version.where(:item_type => 'ButtonSound', :item_id => s.id).count).to eq(0)
    end
    
    it "should remove all board connections" do
      u1 = User.create
      u2 = User.create
      u3 = User.create
      b = Board.create(:user => u1)
      u1.settings['preferences']['home_board'] = {'key' => b.key, 'id' => b.global_id}
      u1.save
      u2.settings['preferences']['home_board'] = {'key' => b.key, 'id' => b.global_id}
      u2.save
      u3.settings['preferences']['home_board'] = {'key' => b.key, 'id' => b.global_id}
      u3.save
      Worker.process_queues
      expect(UserBoardConnection.where(:board_id => b.id).count).to eq(3)
      Flusher.flush_board(b.global_id, b.key)
      expect(UserBoardConnection.where(:board_id => b.id).count).to eq(0)
    end
    
    it "should remove the board as the home board for any users" do
      u1 = User.create
      u2 = User.create
      u3 = User.create
      b = Board.create(:user => u1)
      u1.settings['preferences']['home_board'] = {'key' => b.key, 'id' => b.global_id}
      u1.save
      u2.settings['preferences']['home_board'] = {'key' => b.key, 'id' => b.global_id}
      u2.save
      u3.settings['preferences']['home_board'] = {'key' => b.key, 'id' => b.global_id}
      u3.save
      Worker.process_queues
      expect(UserBoardConnection.where(:board_id => b.id).count).to eq(3)
      Flusher.flush_board(b.global_id, b.key)
      expect(UserBoardConnection.where(:board_id => b.id).count).to eq(0)
      expect(u1.reload.settings['preferences']['home_board']).to eq(nil)
      expect(u2.reload.settings['preferences']['home_board']).to eq(nil)
      expect(u3.reload.settings['preferences']['home_board']).to eq(nil)
    end
    
    it "should remove orphan files from remote storage" do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.create(:user => u)
      i = ButtonImage.create(:removable => true, :url => "http://www.example.com/pic.png")
      i2 = ButtonImage.create(:removable => false, :url => "http://www.example.com/pic2.png")
      i3 = ButtonImage.create(:removable => true, :url => "http://www.example.com/pic3.png")
      BoardButtonImage.connect(b.id, [{:id => i.global_id}, {:id => i2.global_id}, {:id => i3.global_id}])
      BoardButtonImage.connect(b2.id, [{:id => i3.global_id}])
      s = ButtonSound.create(:removable => true, :url => "http://www.example.com/sound.mp3")
      BoardButtonSound.create(:board_id => b.id, :button_sound_id => s.id)
      expect(i.removable).to eq(true)
      expect(i2.removable).to eq(false)
      expect(i3.removable).to eq(true)
      expect(s.removable).to eq(true)

      expect(Uploader).to receive(:remote_remove).with("http://www.example.com/pic.png")
      expect(Uploader).to receive(:remote_remove).with("http://www.example.com/sound.mp3")
      expect(Uploader).not_to receive(:remote_remove).with("http://www.example.com/pic2.png")
      expect(Uploader).not_to receive(:remote_remove).with("http://www.example.com/pic3.png")
      
      Flusher.flush_board(b.global_id, b.key)
      Worker.process_queues
      expect(ButtonImage.count).to eq(1)
      expect(ButtonSound.count).to eq(0)
      expect(BoardButtonImage.where(:board_id => b.id).count).to eq(0)
      expect(BoardButtonSound.where(:board_id => b.id).count).to eq(0)
      expect(Board.where(:id => b.id).count).to eq(0)
    end
    
    it "should support aggressive flushing" do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.create(:user => u)
      i = ButtonImage.create(:removable => true, :url => "http://www.example.com/pic.png")
      i2 = ButtonImage.create(:removable => false, :url => "http://www.example.com/pic2.png")
      i3 = ButtonImage.create(:removable => true, :url => "http://www.example.com/pic3.png")
      BoardButtonImage.connect(b.id, [{:id => i.global_id}, {:id => i2.global_id}, {:id => i3.global_id}])
      BoardButtonImage.connect(b2.id, [{:id => i3.global_id}])
      s = ButtonSound.create(:removable => true, :url => "http://www.example.com/sound.mp3")
      BoardButtonSound.create(:board_id => b.id, :button_sound_id => s.id)
      expect(i.removable).to eq(true)
      expect(i2.removable).to eq(false)
      expect(i3.removable).to eq(true)
      expect(s.removable).to eq(true)

      expect(Uploader).to receive(:remote_remove).with("http://www.example.com/pic.png")
      expect(Uploader).to receive(:remote_remove).with("http://www.example.com/sound.mp3")
      expect(Uploader).not_to receive(:remote_remove).with("http://www.example.com/pic2.png")
      expect(Uploader).to receive(:remote_remove).with("http://www.example.com/pic3.png")
      
      Flusher.flush_board(b.global_id, b.key, true)
      Worker.process_queues
      expect(ButtonImage.count).to eq(0)
      expect(ButtonSound.count).to eq(0)
      expect(BoardButtonImage.where(:board_id => b.id).count).to eq(0)
      expect(BoardButtonSound.where(:board_id => b.id).count).to eq(0)
      expect(Board.where(:id => b.id).count).to eq(0)
    end
  end
  
  describe "flush_user_boards" do
    it "should call find_user" do
      u = User.create
      expect(Flusher).to receive(:find_user).with(u.global_id, u.user_name).and_return(u)
      Flusher.flush_user_boards(u.global_id, u.user_name)
    end
    
    it "should call flush_board for all the user's boards" do
      u = User.create
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b3 = Board.create(:user => u)
      expect(Flusher).to receive(:flush_board).with(b1.global_id, b1.key, true)
      expect(Flusher).to receive(:flush_board).with(b2.global_id, b2.key, true)
      expect(Flusher).to receive(:flush_board).with(b3.global_id, b3.key, true)
      Flusher.flush_user_boards(u.global_id, u.user_name)
    end
  end
  
  describe "flush_user_completely" do
    it "should call find_user" do
      u = User.create
      expect(Flusher).to receive(:find_user).with(u.global_id, u.user_name).exactly(3).times.and_return(u)
      Flusher.flush_user_completely(u.global_id, u.user_name)
    end
    
    it "should call flush_user_logs" do
      u = User.create
      expect(Flusher).to receive(:flush_user_logs).with(u.global_id, u.user_name)
      Flusher.flush_user_completely(u.global_id, u.user_name)
    end
    
    it "should call flush_user_boards" do
      u = User.create
      expect(Flusher).to receive(:flush_user_boards).with(u.global_id, u.user_name)
      Flusher.flush_user_completely(u.global_id, u.user_name)
    end
    
    it "should remove the user's devices, including any versions" do
      u = User.create
      d = Device.create(:user => u)
      Flusher.flush_user_completely(u.global_id, u.user_name)
      expect(Device.where(:user_id => u.id).count).to eq(0)
    end
    
    it "should remove the user's utterances, including any versions" do
      u = User.create
      ut = Utterance.create(:user => u)
      Flusher.flush_user_completely(u.global_id, u.user_name)
      expect(Utterance.where(:user_id => u.id).count).to eq(0)
    end
    
    it "should remove any public comments by the user"
    
    it "should remove identity from any log notes recorded on other users by the user" do
      u = User.create
      u2 = User.create
      d = Device.create(:user => u)
      LogSession.create(:user => u, :author => u2, :device => d)
      expect(LogSession.where(:author_id => u2.id).count).to eq(1)
      expect(LogSession.where(:user_id => u.id).count).to eq(1)

      Flusher.flush_user_completely(u2.global_id, u2.user_name)
      expect(LogSession.where(:author_id => u2.id).count).to eq(0)
      expect(LogSession.where(:user_id => u.id).count).to eq(1)
    end
    
    it "should call flush_record for the user" do
      u = User.create
      expect(Flusher).to receive(:flush_record).with(u, u.id, u.class.to_s)
      Flusher.flush_user_completely(u.global_id, u.user_name)
    end
  end
end
