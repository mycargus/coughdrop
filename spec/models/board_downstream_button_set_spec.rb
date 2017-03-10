require 'spec_helper'

describe BoardDownstreamButtonSet, :type => :model do
  it "should generate defaults" do
    bs = BoardDownstreamButtonSet.create
    expect(bs.data).not_to eq(nil)
    expect(bs.data['buttons']).to eq([])
    expect(bs.data['button_count']).to eq(0)
    expect(bs.data['board_count']).to eq(0)
  end
  
  describe "update_for" do
    it "should do nothing if a matching board does not exist" do
      res = BoardDownstreamButtonSet.update_for('asdf')
      expect(res).to eq(nil)
      expect(BoardDownstreamButtonSet.count).to eq(0)
    end
    
    it "should generate a button set for the specified board id" do
      u = User.create
      b = Board.create(:user => u)
      bs = BoardDownstreamButtonSet.update_for(b.global_id)
      expect(bs).not_to eq(nil)
      expect(bs.board_id).to eq(b.id)
      expect(bs.data['buttons']).to eq([])
    end
    
    it "should include buttons from the current board" do
      u = User.create
      b = Board.create(:user => u)
      b.process({'buttons' => [
        {'id' => 1, 'label' => 'hat'},
        {'id' => 2, 'label' => 'car', 'hidden' => true}
      ]})
      bs = BoardDownstreamButtonSet.update_for(b.global_id)
      expect(bs).not_to eq(nil)
      expect(bs.data['buttons'].length).to eq(2)
      expect(bs.data['buttons'][0]).to eq({
        'id' => 1,
        'label' => 'hat',
        'board_id' => b.global_id,
        'board_key' => b.key,
        'depth' => 0,
        'hidden' => false,
        'image' => nil,
        'link_disabled' => false,
        'vocalization' => nil,
        'locale' => 'en'
      })
      expect(bs.data['buttons'][1]).to eq({
        'id' => 2,
        'label' => 'car',
        'board_id' => b.global_id,
        'board_key' => b.key,
        'depth' => 0,
        'hidden' => true,
        'image' => nil,
        'link_disabled' => false,
        'vocalization' => nil,
        'locale' => 'en'
      })
    end
    
    it "should include buttons from downstream boards" do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b.process({'buttons' => [
        {'id' => 1, 'label' => 'hat', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}},
        {'id' => 2, 'label' => 'car'}
      ]}, :user => u)
      b2.process({'buttons' => [
        {'id' => 1, 'label' => 'yellow'}
      ]})
      bs = BoardDownstreamButtonSet.update_for(b.global_id)
      expect(bs).not_to eq(nil)
      expect(bs.data['buttons'].length).to eq(3)
      expect(bs.data['buttons'][2]).to eq({
        'id' => 1,
        'label' => 'yellow',
        'board_id' => b2.global_id,
        'board_key' => b2.key,
        'depth' => 1,
        'hidden' => false,
        'image' => nil,
        'link_disabled' => false,
        'vocalization' => nil,
        'locale' => 'en'
      })
    end
    
    it "should include link details on buttons that link to other boards" do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b.process({'buttons' => [
        {'id' => 1, 'label' => 'hat', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}},
        {'id' => 2, 'label' => 'car'}
      ]}, :user => u)
      b2.process({'buttons' => [
        {'id' => 1, 'label' => 'yellow'}
      ]})
      bs = BoardDownstreamButtonSet.update_for(b.global_id)
      expect(bs).not_to eq(nil)
      expect(bs.data['buttons'].length).to eq(3)
      expect(bs.data['buttons'][0]).to eq({
        'id' => 1,
        'label' => 'hat',
        'board_id' => b.global_id,
        'board_key' => b.key,
        'depth' => 0,
        'hidden' => false,
        'image' => nil,
        'link_disabled' => false,
        'vocalization' => nil,
        'preferred_link' => true,
        'linked_board_id' => b2.global_id,
        'linked_board_key' => b2.key,
        'locale' => 'en'
      })
    end
    
    it "should not include link details on linked buttons that point to nowhere" do
      u = User.create
      b = Board.create(:user => u)
      b.settings['buttons'] = [
        {'id' => 1, 'label' => 'hat', 'load_board' => {'id' => '1_12345', 'key' => 'hat/man'}},
        {'id' => 2, 'label' => 'car'}
      ]
      b.save
      bs = BoardDownstreamButtonSet.update_for(b.global_id)
      expect(bs).not_to eq(nil)
      expect(bs.data['buttons'].length).to eq(2)
      expect(bs.data['buttons'][0]).to eq({
        'id' => 1,
        'label' => 'hat',
        'board_id' => b.global_id,
        'board_key' => b.key,
        'depth' => 0,
        'hidden' => false,
        'image' => nil,
        'link_disabled' => false,
        'vocalization' => nil,
        'locale' => 'en'
      })
    end
    
    it "should include buttons only once, even if linked to multiple times" do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b3 = Board.create(:user => u)
      b.process({'buttons' => [
        {'id' => 1, 'label' => 'hat', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}},
        {'id' => 2, 'label' => 'car', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
      ]}, :user => u)
      b2.process({'buttons' => [
        {'id' => 1, 'label' => 'yellow', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
      ]}, :user => u)
      b3.process({'buttons' => [
        {'id' => 1, 'label' => 'black'}
      ]}, :user => u)
      bs = BoardDownstreamButtonSet.update_for(b.global_id)
      expect(bs).not_to eq(nil)
      expect(bs.data['buttons'].length).to eq(4)
      expect(bs.data['buttons'][0]['label']).to eq('hat')
      expect(bs.data['buttons'][0]['preferred_link']).to eq(true)
      expect(bs.data['buttons'][1]['label']).to eq('car')
      expect(bs.data['buttons'][1]['preferred_link']).to eq(true)
      expect(bs.data['buttons'][2]['label']).to eq('yellow')
      expect(bs.data['buttons'][3]['label']).to eq('black')
    end
    
    it "should not get stuck in loops" do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b3 = Board.create(:user => u)
      b.process({'buttons' => [
        {'id' => 1, 'label' => 'hat', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}},
        {'id' => 2, 'label' => 'car', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
      ]}, :user => u)
      b2.process({'buttons' => [
        {'id' => 1, 'label' => 'yellow', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}}
      ]}, :user => u)
      b3.process({'buttons' => [
        {'id' => 1, 'label' => 'black'},
        {'id' => 2, 'label' => 'rushing', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}}
      ]}, :user => u)
      bs = BoardDownstreamButtonSet.update_for(b.global_id)
      expect(bs).not_to eq(nil)
      expect(bs.data['buttons'].length).to eq(5)
      expect(bs.data['buttons'][0]['label']).to eq('hat')
      expect(bs.data['buttons'][0]['preferred_link']).to eq(true)
      expect(bs.data['buttons'][1]['label']).to eq('car')
      expect(bs.data['buttons'][1]['preferred_link']).to eq(true)
      expect(bs.data['buttons'][2]['label']).to eq('yellow')
      expect(bs.data['buttons'][3]['label']).to eq('black')
      expect(bs.data['buttons'][4]['label']).to eq('rushing')
    end
    
    it "should mark the shallowest link to a board as the 'preferred' link" do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b3 = Board.create(:user => u)
      b4 = Board.create(:user => u)
      b5 = Board.create(:user => u)
      b.process({'buttons' => [
        {'id' => 1, 'label' => 'hat', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}},
        {'id' => 2, 'label' => 'car', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}},
        {'id' => 3, 'label' => 'noodle', 'load_board' => {'id' => b5.global_id, 'key' => b5.key}}
      ]}, :user => u)
      b2.process({'buttons' => [
        {'id' => 1, 'label' => 'yellow', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}},
        {'id' => 2, 'label' => 'quarter', 'load_board' => {'id' => b4.global_id, 'key' => b4.key}}
      ]}, :user => u)
      b3.process({'buttons' => [
        {'id' => 1, 'label' => 'black'},
        {'id' => 2, 'label' => 'rushing', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}}
      ]}, :user => u)
      b4.process({'buttons' => [
        {'id' => 1, 'label' => 'zebra', 'load_board' => {'id' => b5.global_id, 'key' => b5.key}},
        {'id' => 2, 'label' => 'promote', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}}
      ]}, :user => u)
      b5.process({'buttons' => [
        {'id' => 1, 'label' => 'brand', 'load_board' => {'id' => b3.global_id, 'key' => b3.key}},
        {'id' => 2, 'label' => 'alternate', 'load_board' => {'id' => b.global_id, 'key' => b.key}}
      ]}, :user => u)
      bs = BoardDownstreamButtonSet.update_for(b.global_id)
      expect(bs).not_to eq(nil)
      expect(bs.data['buttons'].length).to eq(11)
      expect(bs.data['buttons'][0]['label']).to eq('hat')
      expect(bs.data['buttons'][0]['preferred_link']).to eq(true)
      expect(bs.data['buttons'][1]['label']).to eq('car')
      expect(bs.data['buttons'][1]['preferred_link']).to eq(true)
      expect(bs.data['buttons'][2]['label']).to eq('noodle')
      expect(bs.data['buttons'][2]['preferred_link']).to eq(true)
      expect(bs.data['buttons'][3]['label']).to eq('yellow')
      expect(bs.data['buttons'][3]['depth']).to eq(1)
      expect(bs.data['buttons'][4]['label']).to eq('quarter')
      expect(bs.data['buttons'][4]['depth']).to eq(1)
      expect(bs.data['buttons'][5]['label']).to eq('black')
      expect(bs.data['buttons'][5]['depth']).to eq(1)
      expect(bs.data['buttons'][6]['label']).to eq('rushing')
      expect(bs.data['buttons'][6]['depth']).to eq(1)
      expect(bs.data['buttons'][7]['label']).to eq('brand')
      expect(bs.data['buttons'][7]['depth']).to eq(1)
      expect(bs.data['buttons'][8]['label']).to eq('alternate')
      expect(bs.data['buttons'][8]['depth']).to eq(1)
      expect(bs.data['buttons'][9]['label']).to eq('zebra')
      expect(bs.data['buttons'][9]['depth']).to eq(2)
      expect(bs.data['buttons'][10]['label']).to eq('promote')
      expect(bs.data['buttons'][10]['depth']).to eq(2)
    end
    
    it "should trigger an update when a board's content has changed" do
      u = User.create
      b = Board.create(:user => u)
      b.process({'buttons' => [
        {'id' => 1, 'label' => 'jump'}
      ]})
      Worker.process_queues
      Worker.process_queues
      bs = b.reload.board_downstream_button_set
      expect(bs).not_to eq(nil)
      expect(bs.data['buttons'].length).to eq(1)
    end
    
    it "should trigger an update when a downstream board's content has changed" do
      u = User.create
      b = Board.create(:user => u)
      b2 = Board.create(:user => u)
      b.process({'buttons' => [
        {'id' => 1, 'label' => 'jump', 'load_board' => {'id' => b2.global_id, 'key' => b2.key}}
      ]}, :user => u)
      b2.process({'buttons' => [
        {'id' => 1, 'label' => 'blouse'}
      ]}, :user => u)
      Worker.process_queues
      Worker.process_queues
      
      bs = b.reload.board_downstream_button_set
      expect(bs).not_to eq(nil)
      expect(bs.data['buttons'].length).to eq(2)
      bs2 = b2.reload.board_downstream_button_set
      expect(bs2).not_to eq(nil)
      expect(bs2.data['buttons'].length).to eq(1)
      
      b2.reload.process({'buttons' => [
        {'id' => 1, 'label' => 'blouse'},
        {'id' => 2, 'label' => 'banana'}
      ]}, :user => u)

      Worker.process_queues
      expect(Worker.scheduled?(BoardDownstreamButtonSet, :perform_action, {'method' => 'update_for', 'arguments' => [b2.global_id]})).to eq(true)
      Worker.process_queues
      expect(Worker.scheduled?(BoardDownstreamButtonSet, :perform_action, {'method' => 'update_for', 'arguments' => [b.global_id]})).to eq(true)
      BoardDownstreamButtonSet.update_for(b.global_id)
      BoardDownstreamButtonSet.update_for(b2.global_id)
      
      bs2.reload
      expect(bs2).not_to eq(nil)
      expect(bs2.data['buttons'].length).to eq(2)
      bs.reload
      expect(bs).not_to eq(nil)
      expect(bs.data['buttons'].length).to eq(3)
    end
  end
end

