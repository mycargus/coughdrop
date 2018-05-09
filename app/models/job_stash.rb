class JobStash < ApplicationRecord
  include GlobalId
  include SecureSerialize

  secure_serialize :data

  def self.flush_old_records
    JobStash.where(['created_at < ?', 4.weeks.ago]).delete_all
  end
end
