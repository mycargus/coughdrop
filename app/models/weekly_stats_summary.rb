class WeeklyStatsSummary < ActiveRecord::Base
  include SecureSerialize
  include GlobalId
  include Async
  replicated_model  
  
  secure_serialize :data  
  before_save :generate_defaults  
  after_save :schedule_badge_check
  
  def schedule_badge_check
    UserBadge.schedule_once(:check_for, self.related_global_id(self.user_id), self.global_id)
    true
  end
  
  def generate_defaults
    found_ids = [self.user_id, self.board_id].compact.length
    raise "no summary index defined" if found_ids == 0
    true
  end
  
  def self.update_for(log_session_id, all=false)
    log_session = LogSession.find_by_global_id(log_session_id)
    return if !log_session || log_session.log_type != 'session'
    return unless log_session.user_id && log_session.started_at && log_session.data && log_session.data['stats']
    # TODO: if log_session.started_at ever gets updated in a way that changes cweek then
    # multiple weeks need to be updated 
    start_at = log_session.started_at.utc.beginning_of_week(:sunday)
    end_at = log_session.started_at.utc.end_of_week(:sunday)
    cweek = start_at.to_date.cweek
    cwyear = start_at.to_date.cwyear
    weekyear = (cwyear * 100) + cweek

    summary = WeeklyStatsSummary.find_or_create_by(:weekyear => weekyear, :user_id => (all ? 0 : log_session.user_id))
    sessions = Stats.find_sessions((all ? 'all' : log_session.user.global_id), {:start_at => start_at, :end_at => end_at})
    
    total_stats = Stats.init_stats(sessions)
    days = {}
    start_at.to_date.upto(end_at.to_date) do |date|
      day_sessions = sessions.select{|s| s.started_at.to_date == date }
      day_stats = Stats.init_stats(day_sessions)
      groups = []
      
      day_sessions.group_by{|s| [s.geo_cluster_global_id, s.ip_cluster_global_id, s.device_global_id] }.each do |ids, group_sessions|
        geo_cluster_id, ip_cluster_id, device_id = ids
        group_stats = Stats.stats_counts(group_sessions, [day_stats, total_stats])
        group_stats['geo_cluster_id'] = geo_cluster_id
        group_stats['ip_cluster_id'] = ip_cluster_id
        group_stats['device_id'] = device_id
        
        group_stats.merge!(Stats.touch_stats(group_sessions))
        group_stats.merge!(Stats.device_stats(group_sessions))
        group_stats.merge!(Stats.sensor_stats(group_sessions))
        group_stats.merge!(Stats.time_block_use_for_sessions(group_sessions))
        group_stats.merge!(Stats.parts_of_speech_stats(group_sessions))
        group_stats[:locations] = Stats.location_use_for_sessions(group_sessions)
        groups << group_stats
      end
      
      # TODO: cache this day object, maybe in advance
      day_stats.merge!(Stats.touch_stats(day_sessions))
      day_stats.merge!(Stats.device_stats(day_sessions))
      day_stats.merge!(Stats.sensor_stats(day_sessions))
      day_stats.merge!(Stats.time_block_use_for_sessions(day_sessions))
      day_stats.merge!(Stats.parts_of_speech_stats(day_sessions))
      day_stats[:locations] = Stats.location_use_for_sessions(day_sessions)
      
      days[date.to_s] = {
        'total' => day_stats,
        'group_counts' => groups
      }
    end

    total_stats.merge!(Stats.touch_stats(sessions))
    total_stats.merge!(Stats.device_stats(sessions))
    total_stats.merge!(Stats.sensor_stats(sessions))
    total_stats.merge!(Stats.time_block_use_for_sessions(sessions))
    total_stats.merge!(Stats.parts_of_speech_stats(sessions))
    total_stats[:days] = days
    total_stats[:locations] = Stats.location_use_for_sessions(sessions)
    
    summary.data ||= {}
    summary.data['stats'] = total_stats
    summary.data['session_ids'] = sessions.map(&:global_id)
    summary.save
    
    # TODO: create board-aligned stat summaries as well
  end
end
