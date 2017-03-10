require 'spec_helper'

describe UpstreamDownstream, :type => :model do
  describe "immediately_downstream_board_ids" do
    it "should always keep this exactly in sync with data from buttons list" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => '123'}},
        {'id' => 2, 'load_board' => {'id' => '234'}}
      ]
      b.save
      expect(b.settings['immediately_downstream_board_ids']).to eq(['123', '234'])
      
      b.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => '234'}},
        {'id' => 2, 'load_board' => {'id' => '345'}},
        {'id' => 3, 'load_board' => {'id' => '456'}}
      ]
      b.save
      expect(b.settings['immediately_downstream_board_ids']).to eq(['234', '345', '456'])

      b.settings['buttons'] = []
      b.save
      expect(b.settings['immediately_downstream_board_ids']).to eq([])
    end
  end
  
  describe "downstream_board_ids" do
    it "should generate the correct list of downstream boards" do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b3 = Board.create(:user => u)
      b2.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b3.global_id}}
      ]
      b2.save
      Worker.flush_queues
      b.save
      b.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b2.global_id}}
      ]
      b.save
      expect(Worker.scheduled?(Board, 'perform_action', {'id' => b.id, 'method' => 'track_downstream_boards!', 'arguments' => [[], nil]})).to eq(true)
      Worker.process_queues
      expect(b.reload.settings['downstream_board_ids']).to eq([b2.global_id, b3.global_id])
    end
    
    it "should not track downstream boards unless there was a change or it is called manually" do
      u = User.create
      b = Board.create(:user => u)
      expect(Worker.scheduled?(Board, 'perform_action', {'id' => b.id, 'method' => 'track_downstream_boards!', 'arguments' => [[], nil]})).to eq(true)
      Worker.process_queues
      b.save
      expect(Worker.scheduled?(Board, 'perform_action', {'id' => b.id, 'method' => 'track_downstream_boards!', 'arguments' => [[], nil]})).to eq(false)
      b.settings['name'] = "Cool Board"
      b.save
      expect(Worker.scheduled?(Board, 'perform_action', {'id' => b.id, 'method' => 'track_downstream_boards!', 'arguments' => [[], nil]})).to eq(false)
      b.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => '123'}},
        {'id' => 2, 'load_board' => {'id' => '234'}}
      ]
      b.instance_variable_set('@buttons_changed', true)
      b.save
      expect(Worker.scheduled?(Board, 'perform_action', {'id' => b.id, 'method' => 'track_downstream_boards!', 'arguments' => [[], true]})).to eq(true)
      Worker.flush_queues
      b.save
      expect(Worker.scheduled?(Board, 'perform_action', {'id' => b.id, 'method' => 'track_downstream_boards!', 'arguments' => [[], nil]})).to eq(false)
      b.settings['buttons'] = [
        {'id' => 1},
        {'id' => 2, 'load_board' => {'id' => '234'}},
        {'id' => 3, 'load_board' => {'id' => '123'}}
      ]
      b.save
      expect(Worker.scheduled?(Board, 'perform_action', {'id' => b.id, 'method' => 'track_downstream_boards!', 'arguments' => [[], nil]})).to eq(false)
    end
    
    it "should push correct list up through all affected boards when there is a change" do
      u = User.create
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b3 = Board.create(:user => u)
      b1.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b2.global_id}}
      ]
      b1.save
      Worker.process_queues
      expect(b3.reload.settings['downstream_board_ids'].sort).to eq([].sort)
      expect(b2.reload.settings['downstream_board_ids'].sort).to eq([].sort)
      expect(b1.reload.settings['downstream_board_ids'].sort).to eq([b2.global_id].sort)
      b2.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b3.global_id}}
      ]
      b2.save
      Worker.process_queues
      expect(b3.reload.settings['downstream_board_ids'].sort).to eq([].sort)
      expect(b2.reload.settings['downstream_board_ids'].sort).to eq([b3.global_id].sort)
      expect(b1.reload.settings['downstream_board_ids'].sort).to eq([b2.global_id, b3.global_id].sort)
      b3.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b1.global_id}}
      ]
      b3.save
      Worker.process_queues
      Worker.process_queues
      Worker.process_queues
      expect(b3.reload.settings['downstream_board_ids'].sort).to eq([b1.global_id, b2.global_id].sort)
      expect(b2.reload.settings['downstream_board_ids'].sort).to eq([b3.global_id, b1.global_id].sort)
      expect(b1.reload.settings['downstream_board_ids'].sort).to eq([b2.global_id, b3.global_id].sort)
    end
    
    it "should not get stuck in a job scheduling loop when tracking streams" do
      expect(Worker.queues_empty?).to eq(true)
      u = User.create
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b3 = Board.create(:user => u)
      b1.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b2.global_id}}
      ]
      b1.save
      Worker.process_queues
      Worker.process_queues
      Worker.process_queues
      Worker.process_queues
      expect(Worker.queues_empty?).to eq(true)
      expect(b3.reload.settings['downstream_board_ids'].sort).to eq([].sort)
      expect(b2.reload.settings['downstream_board_ids'].sort).to eq([].sort)
      expect(b1.reload.settings['downstream_board_ids'].sort).to eq([b2.global_id].sort)
      b2.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b3.global_id}}
      ]
      b2.save
      Worker.process_queues
      Worker.process_queues
      Worker.process_queues
      Worker.process_queues
      expect(Worker.queues_empty?).to eq(true)
      expect(b3.reload.settings['downstream_board_ids'].sort).to eq([].sort)
      expect(b2.reload.settings['downstream_board_ids'].sort).to eq([b3.global_id].sort)
      expect(b1.reload.settings['downstream_board_ids'].sort).to eq([b2.global_id, b3.global_id].sort)
      b3.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b1.global_id}}
      ]
      b3.save
      Worker.process_queues
      Worker.process_queues
      Worker.process_queues
      Worker.process_queues
      Worker.process_queues
      expect(Worker.queues_empty?).to eq(true)
      expect(b3.reload.settings['downstream_board_ids'].sort).to eq([b1.global_id, b2.global_id].sort)
      expect(b2.reload.settings['downstream_board_ids'].sort).to eq([b3.global_id, b1.global_id].sort)
      expect(b1.reload.settings['downstream_board_ids'].sort).to eq([b2.global_id, b3.global_id].sort)
    end
    
    it "should update button counts" do
      u = User.create
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b3 = Board.create(:user => u)
      b1.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b2.global_id}},
        {'id' => 2}
      ]
      b1.save
      Worker.process_queues
      expect(b3.reload.settings['downstream_board_ids'].sort).to eq([].sort)
      expect(b3.settings['total_buttons']).to eq(0)
      expect(b3.settings['unlinked_buttons']).to eq(0)
      expect(b2.reload.settings['downstream_board_ids'].sort).to eq([].sort)
      expect(b2.settings['total_buttons']).to eq(0)
      expect(b2.settings['unlinked_buttons']).to eq(0)
      expect(b1.reload.settings['downstream_board_ids'].sort).to eq([b2.global_id].sort)
      expect(b1.settings['total_buttons']).to eq(2)
      expect(b1.settings['unlinked_buttons']).to eq(1)
      b2.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b3.global_id}},
        {'id' => 2},
        {'id' => 3}
      ]
      b2.save
      Worker.process_queues
      expect(b3.reload.settings['downstream_board_ids'].sort).to eq([].sort)
      expect(b3.settings['total_buttons']).to eq(0)
      expect(b3.settings['unlinked_buttons']).to eq(0)
      expect(b2.reload.settings['downstream_board_ids'].sort).to eq([b3.global_id].sort)
      expect(b2.settings['total_buttons']).to eq(3)
      expect(b2.settings['unlinked_buttons']).to eq(2)
      expect(b1.reload.settings['downstream_board_ids'].sort).to eq([b2.global_id, b3.global_id].sort)
      expect(b1.settings['total_buttons']).to eq(5)
      expect(b1.settings['unlinked_buttons']).to eq(3)
      b3.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b1.global_id}},
        {'id' => 6}
      ]
      b3.save
      Worker.process_queues
      Worker.process_queues
      expect(b3.reload.settings['downstream_board_ids'].sort).to eq([b1.global_id, b2.global_id].sort)
      expect(b3.settings['total_buttons']).to eq(7)
      expect(b3.settings['unlinked_buttons']).to eq(4)
      expect(b2.reload.settings['downstream_board_ids'].sort).to eq([b3.global_id, b1.global_id].sort)
      expect(b2.settings['total_buttons']).to eq(7)
      expect(b2.settings['unlinked_buttons']).to eq(4)
      expect(b1.reload.settings['downstream_board_ids'].sort).to eq([b2.global_id, b3.global_id].sort)
      expect(b1.settings['total_buttons']).to eq(7)
      expect(b1.settings['unlinked_buttons']).to eq(4)

      b3.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b1.global_id}},
        {'id' => 4},
        {'id' => 5}
      ]
      b3.instance_variable_set('@buttons_changed', true)
      b3.instance_variable_set('@button_links_changed', true)
      b3.save
      Worker.process_queues
      Worker.process_queues
      expect(b3.reload.settings['downstream_board_ids'].sort).to eq([b1.global_id, b2.global_id].sort)
      expect(b3.settings['total_buttons']).to eq(8)
      expect(b3.settings['unlinked_buttons']).to eq(5)
      expect(b2.reload.settings['downstream_board_ids'].sort).to eq([b3.global_id, b1.global_id].sort)
      expect(b2.settings['total_buttons']).to eq(8)
      expect(b2.settings['unlinked_buttons']).to eq(5)
      expect(b1.reload.settings['downstream_board_ids'].sort).to eq([b2.global_id, b3.global_id].sort)
      expect(b1.settings['total_buttons']).to eq(8)
      expect(b1.settings['unlinked_buttons']).to eq(5)
    end
  end

  describe "immediately_upstream_board_ids" do
    it "should ping downstream only when list changes" do
      u = User.create
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u)
      
      b1.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b2.global_id}}
      ]
      b1.save

      allow(Board).to receive(:find_all_by_global_id).with([b2.global_id]).and_return([b2]).at_least(1).times
      allow(Board).to receive(:find_all_by_global_id).with([]).and_return([]).at_least(1).times
      expect(b2).to receive(:add_upstream_board_id!).with(b1.global_id).at_least(1).times
      Worker.process_queues      

      b1.save
      expect(b2).not_to receive(:add_upstream_board_id!).with(b1.global_id)
      Worker.process_queues      
    end
    
    it "should update any_upstream attribute" do
      u = User.create
      b1 = Board.create(:user => u)
      b2 = Board.create(:user => u)
      
      b1.settings['buttons'] = [
        {'id' => 1, 'load_board' => {'id' => b2.global_id}}
      ]
      b1.save
      Worker.process_queues

      b1.save
      Worker.process_queues
      b2.reload
      expect(b2.any_upstream).to eq(true)
    end
    
    it "should remove itself from immediately downstream boards when a button link is removed" 
  end  
end
