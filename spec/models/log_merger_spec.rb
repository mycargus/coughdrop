require 'spec_helper'

describe LogMerger, :type => :model do
  it 'should have generate a merge_at value' do
    m = LogMerger.create
    expect(m.merge_at).to be > Time.now
    expect(m.started).to_not eq(true)
  end
end
