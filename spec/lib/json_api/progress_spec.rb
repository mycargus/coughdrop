require 'spec_helper'

describe JsonApi::Progress do
  it "should have defined pagination defaults" do
    expect(JsonApi::Progress::TYPE_KEY).to eq('progress')
    expect(JsonApi::Progress::DEFAULT_PAGE).to eq(10)
    expect(JsonApi::Progress::MAX_PAGE).to eq(25)
  end

  describe "build_json" do
    it "should not include unlisted settings" do
      p = Progress.new(settings: {'hat' => 'black'})
      expect(JsonApi::Progress.build_json(p).keys).not_to be_include('hat')
    end
    
    it "should return appropriate values" do
      p = Progress.new(settings: {})
      ['id', 'status_url', 'status'].each do |key|
        expect(JsonApi::Progress.build_json(p).keys).to be_include(key)
      end
      expect(JsonApi::Progress.build_json(p).keys).not_to be_include('started_at')
      expect(JsonApi::Progress.build_json(p).keys).not_to be_include('finished_at')
      expect(JsonApi::Progress.build_json(p).keys).not_to be_include('result')
      
      p.started_at = Time.now
      expect(JsonApi::Progress.build_json(p).keys).to be_include('started_at')
      expect(JsonApi::Progress.build_json(p).keys).not_to be_include('finished_at')
      expect(JsonApi::Progress.build_json(p).keys).not_to be_include('result')
      
      p.finished_at = Time.now
      expect(JsonApi::Progress.build_json(p).keys).to be_include('started_at')
      expect(JsonApi::Progress.build_json(p).keys).to be_include('finished_at')
      expect(JsonApi::Progress.build_json(p).keys).to be_include('result')
    end

    it "should flag a progress as errored if it got stuck" do
      p  = Progress.new(settings: {})
      p.updated_at = 6.hours.ago
      p.started_at = 6.hours.ago
      hash = JsonApi::Progress.build_json(p)
      expect(hash['status']).to eq('errored')
      expect(hash['result']['error']).to eq('progress job is taking too long, possibly crashed')
    end
  end
end
