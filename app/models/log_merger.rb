class LogMerger < ApplicationRecord
  belongs_to :log_session
  before_save :generate_defaults
  replicated_model

  def generate_defaults
    self.merge_at ||= 30.minutes.from_now
    self.started ||= false
    true
  end
end
