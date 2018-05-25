require 'spec_helper'

describe JobStash, :type => :model do
  it 'should flush_old_records' do
    j1 = JobStash.create
    j2 = JobStash.create
    j3 = JobStash.create
    JobStash.where(id: [j1.id, j2.id]).update_all(created_at: 6.weeks.ago)
    expect(JobStash.count).to eq(3)
    JobStash.flush_old_records
    expect(JobStash.count).to eq(1)
    expect(JobStash.last).to eq(j3)
  end
end
