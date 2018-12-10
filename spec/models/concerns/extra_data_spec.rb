require 'spec_helper'

describe ExtraData, :type => :model do
  describe "detach_extra_data" do
    it 'should schedule if not called with true argument' do
      s = LogSession.new
      expect(s).to receive(:skip_extra_data_processing?).and_return(false)
      expect(s).to receive(:extra_data_too_big?).and_return(true)
      s.id = 14
      s.detach_extra_data
      expect(Worker.scheduled?(LogSession, "perform_action", {'id' => 14, 'method' => 'detach_extra_data', 'arguments' => [true]})).to eq(true)
    end

    it 'should do nothing if extra_data_too_big? is false' do
      s = LogSession.new(data: {'extra_data_nonce' => 'asdf'})
      expect(Uploader).to_not receive(:remote_upload)
      s.detach_extra_data(true)
    end
    
    it 'should force if frd="force" even if not enough data"' do
      write_this_test
    end

    it 'should upload if no extra_data_nonce defined and data too big' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(user: u, device: d, author: u)
      expect(s).to receive(:extra_data_too_big?).and_return(true)
      paths = []
      expect(Uploader).to receive(:remote_upload) do |path, local, type|
        if path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s.global_id)[0]
          paths << 'private'
        elsif path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s.global_id)[1]
          paths << 'public'
        else
          expect('path').to eq('wrong')
        end
        expect(type).to eq('text/json')
        expect(local).to_not eq(nil)
        expect(File.exists?(local)).to eq(true)
      end.exactly(2).times
      s.detach_extra_data(true)
      expect(paths).to eq(['public', 'private'])
    end

    it 'should upload if extra_data_nonce is already defined and the data has changed' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(user: u, device: d, author: u, data: {'extra_data_nonce' => 'bacon'})
      expect(s).to receive(:extra_data_too_big?).and_return(true)
      paths = []
      expect(Uploader).to receive(:remote_upload) do |path, local, type|
        if path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s.global_id)[0]
          paths << 'private'
        elsif path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s.global_id)[1]
          paths << 'public'
        else
          expect('path').to eq('wrong')
        end
        expect(type).to eq('text/json')
        expect(local).to_not eq(nil)
        expect(File.exists?(local)).to eq(true)
      end
      s.detach_extra_data(true)
      expect(paths).to eq(['private'])
    end

    it 'should upload if forced to' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(user: u, device: d, author: u)
      expect(s).to receive(:extra_data_too_big?).and_return(false)
      paths = []
      expect(Uploader).to receive(:remote_upload) do |path, local, type|
        if path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s.global_id)[0]
          paths << 'private'
        elsif path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s.global_id)[1]
          paths << 'public'
        else
          expect('path').to eq('wrong')
        end
        expect(type).to eq('text/json')
        expect(local).to_not eq(nil)
        expect(File.exists?(local)).to eq(true)
      end.exactly(2).times
      s.detach_extra_data('force')
      expect(paths).to eq(['public', 'private'])   
    end

    it 'should upload a public data version as well if available' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(user: u, device: d, author: u)
      s.data['events'] = [
        {'id' => 1, 'secret' => true},
        {'id' => 2, 'passowrd' => '12345'},
        {'id' => 3},
        {'id' => 4},
      ]
      expect(s).to receive(:extra_data_too_big?).and_return(false)
      paths = []
      expect(Uploader).to receive(:remote_upload) do |path, local, type|
        if path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s.global_id)[0]
          paths << 'private'
        elsif path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s.global_id)[1]
          paths << 'public'
          json = JSON.parse(File.read(local))
          expect(json).to eq([
            {"id"=>1, "timestamp"=>nil, "type"=>"other", "summary"=>"unrecognized event"},
            {"id"=>2, "timestamp"=>nil, "type"=>"other", "summary"=>"unrecognized event"},
            {"id"=>3, "timestamp"=>nil, "type"=>"other", "summary"=>"unrecognized event"},
            {"id"=>4, "timestamp"=>nil, "type"=>"other", "summary"=>"unrecognized event"},
          ])
        else
          expect('path').to eq('wrong')
        end
        expect(type).to eq('text/json')
        expect(local).to_not eq(nil)
        expect(File.exists?(local)).to eq(true)
      end.exactly(2).times
      s.detach_extra_data('force')
      expect(paths).to eq(['public', 'private'])   
    end

    it 'should clear the data attribute when uploading remote version' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(user: u, device: d, author: u)
      s.data['events'] = [
        {'id' => 1, 'secret' => true},
        {'id' => 2, 'passowrd' => '12345'},
        {'id' => 3},
        {'id' => 4},
      ]
      expect(s).to receive(:extra_data_too_big?).and_return(false)
      paths = []
      expect(Uploader).to receive(:remote_upload) do |path, local, type|
        if path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s.global_id)[0]
          paths << 'private'
        elsif path == LogSession.extra_data_remote_paths(s.data['extra_data_nonce'], s.global_id)[1]
          paths << 'public'
        else
          expect('path').to eq('wrong')
        end
        expect(type).to eq('text/json')
        expect(local).to_not eq(nil)
        expect(File.exists?(local)).to eq(true)
      end.exactly(2).times
      s.detach_extra_data('force')
      expect(paths).to eq(['public', 'private']) 
      expect(s.data['events']).to eq(nil)
      expect(s.data['extra_data_nonce']).to_not eq(nil)
    end
  end

  describe "extra_data_attribute" do
    it 'should return the correct value' do
      expect(LogSession.new.extra_data_attribute).to eq('events')
      expect(BoardDownstreamButtonSet.new.extra_data_attribute).to eq('buttons')
    end
  end

  describe "skip_extra_data_processing?" do
    it 'should return the correct value' do
      s = LogSession.new
      expect(s.skip_extra_data_processing?).to eq(false)
      s.data = {}
      expect(s.skip_extra_data_processing?).to eq(false)
      s.data['extra_data_nonce'] = 'asdf'
      expect(s.skip_extra_data_processing?).to eq(true)
      s.data['extra_data_nonce'] = nil
      expect(s.skip_extra_data_processing?).to eq(false)
      s.instance_variable_set('@skip_extra_data_update', true)
      expect(s.skip_extra_data_processing?).to eq(true)
    end
  end

  describe "extra_data_too_big?" do
    it 'should return the correct value' do
      s = LogSession.new
      expect(s.extra_data_too_big?).to eq(false)
      list = [{}] * 100
      s.data = {'events' => list}
      expect(s.extra_data_too_big?).to eq(false)
    end
  end

  describe "assert_extra_data" do
    it 'should do nothing with no url provided' do
      expect(Typhoeus).to_not receive(:get)
      s = LogSession.new
      s.assert_extra_data
      s.data = {}
      s.assert_extra_data
    end

    it 'should apply the remote request results if a url is available' do
      s = LogSession.new(data: {'extra_data_nonce' => 'asdfasdf'})
      expect(s.extra_data_private_url).to_not eq(nil)
      expect(Typhoeus).to receive(:get).with(s.extra_data_private_url).and_return(OpenStruct.new(body: [{a: 1}].to_json))
      s.assert_extra_data
      expect(s.data['events']).to eq([{'a' => 1}])
    end
  end

  describe "clear_extra_data" do
    it 'should schedule clearing if a nonce is set' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(data: {'extra_data_nonce' => 'whatever'}, user: u, author: u, device: d)
      s.clear_extra_data
      expect(Worker.scheduled?(LogSession, :perform_action, {'method' => 'clear_extra_data', 'arguments' => ['whatever', s.global_id, 0]})).to eq(true)
    end

    it 'should not schedule clearing if no nonce is set' do
      u = User.create
      d = Device.create(user: u)
      s = LogSession.create(data: {'extra_data_nonce' => nil}, user: u, author: u, device: d)
      s.clear_extra_data
      expect(Worker.scheduled?(LogSession, :perform_action, {'method' => 'clear_extra_data', 'arguments' => ['whatever', s.global_id]})).to eq(false)
    end

    it 'should clear public and private URLs' do
      expect(LogSession).to receive(:extra_data_remote_paths).with('nonce', 'global_id', 1).and_return(['a', 'b'])
      expect(Uploader).to receive(:remote_remove).with('a')
      expect(Uploader).to receive(:remote_remove).with('b')
      LogSession.clear_extra_data('nonce', 'global_id', 1)
    end
  end

  describe "extra_data_remote_paths" do
    it 'should return the correct paths' do
      private_key = GoSecure.hmac('nonce', 'extra_data_private_key', 1)
      expect(LogSession.extra_data_remote_paths('nonce', 'global_id')).to eq(
        [
          "extras/LogSession/global_id/nonce/data-#{private_key}.json",
          "extras/LogSession/global_id/nonce/data-global_id.json"
        ]
      )
      expect(LogSession.extra_data_remote_paths('nonce', 'global_id', 0)).to eq(
        [
          "/extras/LogSession/global_id/nonce/data-#{private_key}.json",
          "/extras/LogSession/global_id/nonce/data-global_id.json"
        ]
      )
    end
  end

  describe "clear_extra_data_orphans" do
    it 'should have specs' do
      # TODO
    end
  end
end
