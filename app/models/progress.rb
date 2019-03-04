class Progress < ActiveRecord::Base
  include GlobalId
  include SecureSerialize
  protect_global_id
  secure_serialize :settings
  before_save :generate_defaults
  replicated_model
  
  include Permissions
  add_permissions('view' ,['*']) { true }
  
  
  def generate_defaults
    self.settings ||= {}
    self.settings['state'] ||= 'pending'
  end
  
  def start!
    self.started_at = Time.now
    self.settings ||= {}
    self.settings['state'] = 'started'
    self.save!
  end
  
  def finish!
    self.finished_at = Time.now
    self.settings ||= {}
    self.settings['state'] = 'finished'
    self.save!
  end
  
  def error!(e)
    self.settings ||= {}
    self.settings['error'] = e.message.to_s
    self.settings['backtrace'] = e.backtrace.to_s
    self.finished_at = Time.now
    self.settings['state'] = 'errored'
    self.save!
  end
  
  def error_message
    puts ([self.settings['error']] + JSON.parse(self.settings['backtrace'])).join("\n")
    nil
  end
  
  def self.schedule(obj, method, *args)
    # TODO: this (clear_old_progresses) should probably be more of a cron task
    clear_old_progresses
    
    id = nil
    if obj.is_a?(ActiveRecord::Base)
      id = obj.id
      obj = obj.class
    end
    progress = Progress.new
    progress.settings = {
      'class' => obj.to_s,
      'id' => id,
      'method' => method,
      'arguments' => args
    }
    progress.save!
    Worker.schedule_for(:priority, Progress, :perform_action, progress.id)
    progress
  end
  
  def self.as_percent(start_percent, end_percent, &block)
    @@running_progresses ||= {}
    progress = @@running_progresses[Worker.thread_id]
    if progress
      # initialize block
      progress.settings['current_multiplier'] ||= 1.0
      percent = (end_percent - start_percent)
      percent_tally_addition = start_percent * progress.settings['current_multiplier']
      progress.settings['percent_tallies'] ||= []
      full_percent_tally_addition = end_percent * progress.settings['current_multiplier']
      full_percent_tally_addition += progress.settings['percent_tallies'].sum
      
      # prep for progress updates
      progress.settings['percent_tallies'] << percent_tally_addition
      progress.settings['percents_before'] ||= []
      progress.settings['percents_before'] << percent
      progress.settings['current_multiplier'] = (progress.settings['current_multiplier'] * percent).round(4)
      progress.save
      block.call
      
      # tear-down after progress updates
      progress.settings['percent'] = full_percent_tally_addition.round(2)
      progress.settings['percent_tallies'].pop
      progress.settings['percents_before'].pop
      progress.settings['current_multiplier'] = (progress.settings['current_multiplier'] / percent).round(4)
      progress.save
    else
      block.call
    end
  end
  
  def self.update_current_progress(percent, message_key=nil)
    @@running_progresses ||= {}
    progress = @@running_progresses[Worker.thread_id]
    if progress
      if progress.settings['current_multiplier']
        percent *= progress.settings['current_multiplier'] || 1.0
        percent += progress.settings['percent_tallies'].sum
      end
      progress.settings['percent'] = percent.round(2)
      progress.settings['message_key'] = message_key.to_s if message_key
      progress.save
    else
      false
    end
  end
 
  def self.clear_old_progresses
    Progress.where(["finished_at IS NOT NULL AND finished_at < ?", 7.days.ago]).delete_all
  end
  
  def self.perform_action(progress_id)
    progress = Progress.find_by(:id => progress_id)
    @@running_progresses ||= {}
    @@running_progresses[Worker.thread_id] = progress
    progress.start!
    obj = progress.settings['class'].constantize
    if progress.settings['id']
      obj = obj.find_by(:id => progress.settings['id'])
    end
    begin
      Progress.as_percent(0, 1.0) do
        res = obj.send(progress.settings['method'], *progress.settings['arguments'])
        progress.settings['result'] = res
        progress.finish!
      end
    rescue ProgressError => e
      progress.error!(e)
    rescue => e
      progress.error!(e)
      if Rails.env.development?
        raise e
      end
    end
    @@running_progresses[Worker.thread_id] = nil
    progress
  end

  class ProgressError < StandardError
  end
end
