require 'spec_helper'

describe UserBoardConnection, :type => :model do
  it "should always have a value for home" do
    u = UserBoardConnection.create
    expect(u.home).to eq(false)
    u.home = nil
    u.save
    expect(u.home).to eq(false)
  end
  
  it "should be created for home boards" do
    u = User.create
    b = Board.create(:user => u)
    u.settings['preferences']['home_board'] = {'id' => b.global_id, 'key' => b.key}
    u.save
    Worker.process_queues
    expect(UserBoardConnection.count).to eq(1)
    expect(UserBoardConnection.first.home).to eq(true)
  end

  it "should be created for home boards only when tracking boards" do
    u = User.create
    Worker.process_queues
    b = Board.create(:user => u)
    u.settings['preferences']['home_board'] = {'id' => b.global_id, 'key' => b.key}
    u.save
    Worker.process_queues
    expect(UserBoardConnection.count).to eq(0)
    u.process({'preferences' => {'home_board' => {'id' => b.global_id, 'key' => b.key}}})
    Worker.process_queues
    expect(UserBoardConnection.count).to eq(1)
    expect(UserBoardConnection.first.home).to eq(true)
  end
  
  it "should be created for sidebar boards" do
    u = User.create
    b = Board.create(:user => u)
    u.settings['preferences']['sidebar_boards'] = [{'id' => b.global_id, 'key' => b.key}]
    u.save
    Worker.process_queues
    expect(UserBoardConnection.count).to eq(1)
    expect(UserBoardConnection.first.home).to eq(false)
  end
  
  it "should remove orphan boards" do
    u = User.create
    b = Board.create(:user => u)
    expect(UserBoardConnection.count).to eq(0)
    UserBoardConnection.create(:user_id => u.id, :board_id => b.id)
    expect(UserBoardConnection.count).to eq(1)
    u.track_boards(true)
    expect(UserBoardConnection.count).to eq(0)
  end
  
  it "should be created for linked boards" do
    u = User.create
    b = Board.create(:user => u)
    b2 = Board.create(:user => u)
    b.settings['buttons'] = [{'id' => 1, 'load_board' => {'id' => b2.global_id, 'key' => b2.key}}]
    b.save
    u.settings['preferences']['home_board'] = {'id' => b.global_id, 'key' => b.key}
    u.save
    Worker.process_queues
    expect(UserBoardConnection.count).to eq(2)
    expect(UserBoardConnection.where(:board_id => b.id).first.home).to eq(true)
    expect(UserBoardConnection.where(:board_id => b2.id).first.home).to eq(false)
  end
end
