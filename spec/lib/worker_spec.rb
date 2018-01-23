require 'spec_helper'

describe Worker do
  it "should properly flush queues" do
    Worker.schedule(User, 'do_something', 2)
    Worker.flush_queues
    expect(Worker.scheduled?(User, :do_something, 2)).to eq(false)
  end
  
  describe "perform" do
    it "should parse out Worker options and call the appropriate method" do
      expect(User).to receive(:bacon).with(12)
      Worker.perform('User', 'bacon', 12)
      
      expect(Board).to receive(:halo).with(6, {a: 1})
      Worker.perform('Board', :halo, 6, {a: 1})
    end
    
    it "should run scheduled events when told" do
      Worker.schedule(User, :bacon, 12)
      Worker.schedule(Board, :halo, 6, {a: 1})
      expect(User).to receive(:bacon).with(12)
      expect(Board).to receive(:halo).with(6, {'a' => 1})
      Worker.process_queues
    end
    
    it "should catch termination exceptions and re-queue" do
      expect(User).to receive(:bacon).with(12).and_raise(Resque::TermException.new('SIGTERM'))
      Worker.schedule(User, :bacon, 12)
      Worker.process_queues
      expect(Worker.scheduled?(User, :bacon, 12)).to be_truthy
    end
  end
  
  describe "schedule" do
    it "should add to the queue" do
      Worker.schedule(User, 'do_something', 2)
      expect(Worker.scheduled?(User, :do_something, 2)).to be_truthy
      expect(Worker.scheduled?(User, :do_something, 1)).to be_falsey
      Worker.schedule(User, 'do_something', {a: 1, b: [2,3,4], c: {d: 7}})
      expect(Worker.scheduled?(User, :do_something, {a: 1, b: [2,3,4], c: {d: 7}})).to be_truthy
    end

    it "should add to a difference queue" do
      Worker.schedule_for('bacon', User, 'do_something', 2)
      expect(Worker.scheduled?(User, :do_something, 2)).to be_falsey
      expect(Worker.scheduled?(User, :do_something, 1)).to be_falsey
      expect(Worker.scheduled_for?('bacon', User, :do_something, 2)).to be_truthy
      expect(Worker.scheduled_for?('bacon', User, :do_something, 1)).to be_falsey
      Worker.schedule_for('priority', User, 'do_something', {a: 1, b: [2,3,4], c: {d: 7}})
      expect(Worker.scheduled?(User, :do_something, {a: 1, b: [2,3,4], c: {d: 7}})).to be_falsey
      expect(Worker.scheduled_for?('priority', User, :do_something, {a: 1, b: [2,3,4], c: {d: 7}})).to be_truthy
    end
    
    it "should add to the queue from async-enabled models" do
      User.schedule(:hip_hop, 16)
      u = User.create!
      u.schedule(:hip_hop, 17)
      expect(Worker.scheduled?(User, :perform_action, {'method' => 'hip_hop', 'arguments' => [16]})).to be_truthy
      expect(Worker.scheduled?(User, :perform_action, {'id' => u.id, 'method' => 'hip_hop', 'arguments' => [17]})).to be_truthy
    end
  end
  
  describe "perform_at" do
    it "should not log on short jobs" do
      expect(Worker).to receive(:ts).and_return(1469141072, 1469141072 + 10)
      expect(Rails.logger).to_not receive(:error)
      Worker.perform_at(:normal, 'User', 'count')
    end

    it "should log on long-running jobs" do
      expect(Worker).to receive(:ts).and_return(1469141072, 1469141072 + 65)
      expect(Rails.logger).to receive(:error).with("long-running job, User . count (), 65s")
      Worker.perform_at(:normal, 'User', 'count')
    end
    
    it "should not log on semi-long jobs for the slow queue" do
      expect(Worker).to receive(:ts).and_return(1469141072, 1469141072 + (60*2))
      expect(Rails.logger).to_not receive(:error)
      Worker.perform_at(:slow, 'User', 'count')
    end
    
    it "should log on really-long jobs for the slow queue" do
      expect(Worker).to receive(:ts).and_return(1469141072, 1469141072 + (60*11))
      expect(Rails.logger).to receive(:error).with("long-running job, User . count () (expected slow), 660s")
      Worker.perform_at(:slow, 'User', 'count')
    end
  end
  
  describe "scheduled_actions" do
    it "should have list actions" do
      Worker.schedule(User, :something)
      expect(Worker.scheduled_actions.length).to eq(1)
      expect(Worker.scheduled_actions[-1]).to eq({
        'class' => 'Worker', 'args' => ['User', 'something']
      })
      u = User.create
      u.schedule(:do_something, 'cool')
      expect(Worker.scheduled_actions.length).to be >= 2
      expect(Worker.scheduled_actions[-1]).to eq({
        'class' => 'Worker', 'args' => ['User', 'perform_action', {'id' => u.id, 'method' => 'do_something', 'scheduled' => Time.now.to_i, 'arguments' => ['cool']}]
      })
    end
  end

  describe "stop_stuck_workers" do
    it "should have unregister only stuck workers" do
      worker1 = OpenStruct.new({
        :processing => {
          'run_at' => 6.weeks.ago
        }
      })
      worker2 = OpenStruct.new({
        :processing => {
          'run_at' => 1.seconds.ago
        }
      })
      worker3 = OpenStruct.new({
        :processing => {
        }
      })
      expect(Resque).to receive(:workers).and_return([worker1, worker2, worker3])
      expect(worker1).to receive(:unregister_worker)
      expect(worker2).to_not receive(:unregister_worker)
      expect(worker3).to_not receive(:unregister_worker)
      Worker.stop_stuck_workers
    end
  end

  describe "prune_dead_workers" do
    it "should prune dead workers" do
      worker1 = OpenStruct.new
      worker2 = OpenStruct.new
      worker3 = OpenStruct.new
      expect(Resque).to receive(:workers).and_return([worker1, worker2])
      expect(worker1).to receive(:prune_dead_workers)
      expect(worker2).to receive(:prune_dead_workers)
      expect(worker3).to_not receive(:prune_dead_workers)
      Worker.prune_dead_workers
    end
  end

  describe "kill_all_workers" do
    it "should kill all workers" do
      worker1 = OpenStruct.new
      worker2 = OpenStruct.new
      worker3 = OpenStruct.new
      expect(Resque).to receive(:workers).and_return([worker1, worker2])
      expect(worker1).to receive(:unregister_worker)
      expect(worker2).to receive(:unregister_worker)
      expect(worker3).to_not receive(:unregister_worker)
      Worker.kill_all_workers
    end
  end
  
  describe "whodunnit" do
    it "should mark whodunnit correctly" do
      PaperTrail.whodunnit = 'user:bob'
      u = User.create
      expect(u.versions.last.whodunnit).to eq('user:bob')
      expect(u.reload.versions.count).to eq(1)

      u.schedule(:enable_feature, 'bacon')
      Worker.process_queues
      expect(u.reload.versions.count).to eq(1)
      expect(u.versions.last.whodunnit).to eq("user:bob")
    end
  end
end
