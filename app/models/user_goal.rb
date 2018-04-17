class UserGoal < ActiveRecord::Base
  include Processable
  include Permissions
  include Async
  include GlobalId
  include SecureSerialize

  belongs_to :user
  before_save :generate_defaults
  after_save :check_set_as_primary
  after_save :update_template_header
  after_destroy :remove_if_primary
  after_destroy :remove_linked_templates
  replicated_model  

  secure_serialize :settings

  add_permissions('view', ['read_profile']) {|user| self.user && self.user == user }
  add_permissions('view', 'comment', 'edit') {|user| self.user && self.user == user }
  add_permissions('view', ['read_profile']) {|user| self.user && self.user.allows?(user, 'supervise') }
  add_permissions('view', 'comment') {|user| self.user && self.user.allows?(user, 'supervise') }
  add_permissions('view', ['read_profile']) {|user| self.user && self.user.allows?(user, 'edit') }
  add_permissions('view', 'comment', 'edit') {|user| self.user && self.user.allows?(user, 'edit') }
  cache_permissions
  
  def generate_defaults
    self.settings ||= {}
    self.settings['summary'] ||= "user goal"
    self.generate_stats
    self.primary ||= false
    self.primary = false if active == false
    self.template = true if self.template_header
    self.template_header = false if !self.template
    if self.global
      self.template_header = false 
      self.settings['template_header_id'] = nil
    end
    self.settings['max_badge_level'] = self.settings['badges'].length if self.settings['badges']
    self.settings['badge_image_url'] = ((self.settings['badges'] || [])[0] || {})['image_url']
    self.settings['old_template_header_id'] = self.settings['template_header_id'] if self.settings['template_header_id']
    if (self.active || self.global) && !self.settings['started_at']
      self.settings['started_at'] = Time.now.iso8601
    end
    if !self.active && !self.global && !self.settings['ended_at'] && self.settings['started_at']
      self.settings['ended_at'] = Time.now.iso8601
    end
  end
  
  def active_during(start_at, end_at)
    if active
      started = Time.parse(self.settings['started_at']) rescue nil
      return !!(started && started <= end_at)
    else
      started = Time.parse(self.settings['started_at']) rescue nil
      ended = Time.parse(self.settings['ended_at']) rescue nil
      return !!(started && ended && started <= end_at && ended >= start_at)
    end
  end
  
  def update_template_header
    if @skip_update_template_header
      @skip_update_template_header = false
      return
    end
    if self.settings['template_header_id']
      header_id = self.settings['template_header_id']
      if self.settings['template_header_id'] == 'self'
        header_id = self.global_id
      end
      header = UserGoal.find_by_path(header_id)
      header.add_template(self) if header
      header.schedule(:compute_start_ats)
    elsif self.settings['old_template_header_id']
      header = UserGoal.find_by_path(self.settings['old_template_header_id'])
      header.remove_template(self) if header
    end
    true
  end
  
  def compute_start_ats
    self.settings['linked_template_ids'] ||= []
    links = UserGoal.find_all_by_path(self.settings['linked_template_ids'])
    links.each do |goal|
      if goal.settings['next_template_id'] && goal.settings['goal_advances_at']
        next_template = links.detect{|g| g.global_id == goal.settings['next_template_id'] }
        if next_template
          next_template.settings['goal_starts_at'] = goal.settings['goal_advances_at']
          next_template.instance_variable_set('@skip_update_template_header', true)
          next_template.save
        end
      end
    end
  end
  
  def add_template(goal)
    if self.settings['template_header_id'] == 'self'
      self.settings['template_header_id'] = self.global_id
    end
    self.settings['linked_template_ids'] ||= []
    old_ids = self.settings['linked_template_ids']
    self.settings['linked_template_ids'] |= [goal.global_id]
    @skip_update_template_header = true
    self.save #if old_ids != self.settings['linked_template_ids']
  end
  
  def remove_template(goal)
    self.settings['linked_template_ids'] ||= []
    old_ids = self.settings['linked_template_ids']
    self.settings['linked_template_ids'] -= [goal.global_id]
    @skip_update_template_header = true
    self.save #if old_ids != self.settings['linked_template_ids']
  end
  
  def remove_linked_templates
    ids = self.settings['linked_template_ids'] || []
    UserGoal.find_all_by_global_id(ids).each{|g| g.destroy }
  end
  
  def generate_stats
    if self.template_header
      links = self.settings['linked_template_ids'] || []
      self.settings['template_stats'] = {}
      goals = ([self] + UserGoal.find_all_by_global_id(links)).uniq
      self.settings['template_stats']['goals'] = goals.length
      duration = goals.map{|g| g.settings['goal_duration'] || 0 }.sum
      self.settings['template_stats']['total_duration'] = duration if duration > 0
      self.settings['template_stats']['loop'] = self.id && goals.any?{|g| g.settings['next_template_id'] == self.global_id }
      self.settings['template_stats']['badges'] = goals.map{|g| (g.settings && g.settings['stats'] && g.settings['stats']['badges']) || 0 }.sum
    end
    stats = {}
    # TODO: sharding
    sessions = []
    # monthly for all time
    sessions = LogSession.where(:goal_id => self.id).select{|s| s.started_at } if self.id
    stats['monthly'] = {}
    suggested_level = 'monthly'
    # weekly for the past 12 weeks
    stats['weekly'] = {}
    weekly_sessions = sessions.select{|s| s.started_at && s.started_at > 12.weeks.ago }
    suggested_level = 'weekly' if weekly_sessions.length == sessions.length
    # daily for the past 2 weeks
    stats['daily'] = {}
    daily_sessions = sessions.select{|s| s.started_at && s.started_at > 2.weeks.ago }
    suggested_level = 'daily' if daily_sessions.length == weekly_sessions.length
    [[daily_sessions, 'daily'], [weekly_sessions, 'weekly'], [sessions, 'monthly']].each do |sessions, level|
      sessions.each do |session|
        key = session.started_at.utc.iso8601[0, 10]
        key = "#{session.started_at.utc.to_date.cwyear}-#{session.started_at.utc.to_date.cweek.to_s.rjust(2, '0')}" if level == 'weekly'
        key = session.started_at.utc.iso8601[0, 7] if level == 'monthly'
        [key, 'totals'].each do |k|
          stats[level][k] ||= {}
          stats[level][k]['sessions'] ||= 0
          stats[level][k]['sessions'] += 1
          stats[level][k]['positives'] ||= 0
          stats[level][k]['positives'] += session.data['goal']['positives'] if session.data['goal'] && session.data['goal']['positives']
          stats[level][k]['negatives'] ||= 0
          stats[level][k]['negatives'] += session.data['goal']['negatives'] if session.data['goal'] && session.data['goal']['negatives']
          stats[level][k]['statuses'] ||= []
          stats[level][k]['statuses'] << session.data['goal']['status'] if session.data['goal'] && session.data['goal']['status']
        end
      end
      stats[level]['totals'] ||= {
        'sessions' => 0,
        'positives' => 0,
        'negatives' => 0,
        'statuses' => []
      }
    end
    all_statuses = stats['monthly']['totals']['statuses']
    status_tally = 0.0
    positive_tally = 0.0
    status_total = 0.0
    positive_total = 0.0
    last_session = sessions.map(&:started_at).max
    sessions.each do |session|
      diff = last_session - session.started_at
      mult = 1.0
      if diff < 1.week
        mult = 5.0
      elsif diff < 2.weeks
        mult = 3.0
      elsif diff < 1.month
        mult = 2.0
      elsif diff < 3.months
        mult = 1.5
      end
      if session.data['goal']['status']
        status_total += mult
        status_tally += session.data['goal']['status'] * mult
      end
      if session.data['goal']['positives']
        positive_total += (session.data['goal']['positives'] + session.data['goal']['negatives']) * mult
        positive_tally += session.data['goal']['positives'] * mult
      end
    end
    stats['average_status'] = all_statuses.length > 0 ? all_statuses.sum.to_f / all_statuses.length.to_f : 0
    total_tallies = stats['monthly']['totals']['positives'].to_f + stats['monthly']['totals']['negatives'].to_f
    stats['percent_positive'] = total_tallies > 0 ? (stats['monthly']['totals']['positives'].to_f / total_tallies * 100.0) : 0
    stats['weighted_percent_positive'] = positive_total > 0 ? (positive_tally.to_f / positive_total.to_f * 100.0) : 0
    stats['weighted_average_status'] = status_total > 0 ? (status_tally.to_f / status_total.to_f) : 0
    stats['sessions'] = sessions.length
    stats['badges'] = ((self.settings && self.settings['badges']) || []).length
    stats['suggested_level'] = suggested_level
    self.settings ||= {}
    self.settings['stats'] = stats
  end
  
  def goal_code(user)
    raise "user required" unless user
    timestamp = Time.now.to_i.to_s
    rnd = rand(9999999).to_s
    user_id = user.global_id
    str = GoSecure.sha512(timestamp + "_" + user_id, rnd)[0, 20]
    timestamp + "-" + user_id + "-" + rnd + "-" + str
  end
  
  def process_status_from_code(status, code)
    timestamp, user_id, rnd, hash = code.split(/-/)
    user = User.find_by_path(user_id)
    if user && self.user && hash == GoSecure.sha512(timestamp + "_" + user_id, rnd)[0, 20]
      self.settings['used_codes'] ||= []
      self.settings['used_codes'] << [code, Time.now.to_i]
      self.save
      log = LogSession.process_new({
        note: {
          text: ""
        },
        goal_id: self.global_id,
        goal_status: status
      }, {user: self.user, author: user, device: user.devices.first})
      log
    else
      false
    end
  end

  def summary
    self.settings['summary']
  end
  
  def remove_if_primary
    if self.user && self.user.settings && self.user.settings['primary_goal'] && self.user.settings['primary_goal']['id'] == self.global_id
      self.user.update_setting({'primary_goal' => nil})
    end
    true
  end
  
  def self.primary_goal(user)
    # TODO: sharding
    UserGoal.where(:user_id => user.id, :primary => true, :active => true).first
  end

  def self.secondary_goals(user)
    # TODO: sharding
    UserGoal.where(:user_id => user.id, :primary => false, :active => true)
  end  
  
  def check_set_as_primary
    if @set_as_primary
      if self.user && self.user.settings
        # TODO: sharding
        UserGoal.where(:user_id => self.user_id).update_all(:primary => false)
        UserGoal.where(:id => self.id).update_all(:primary => true)
        if !self.user.settings || !self.user.settings['primary_goal'] || self.user.settings['primary_goal']['id'] != self.global_id
          self.user.reload
          self.user.update_setting('primary_goal', {
            'id' => self.global_id,
            'summary' => self.summary
          })
        end
      end
    elsif @clear_primary
      if self.user && self.user.settings
        # TODO: sharding
        UserGoal.where(:user_id => self.user_id).update_all(:primary => false)
        if self.user.settings && self.user.settings['primary_goal']
          self.user.update_setting({'primary_goal' => nil})
        end
      end
    end
    true
  end

  def update_usage(iso8601)
    if self.primary
      user = self.user
      if user.settings && user.settings['primary_goal'] && user.settings['primary_goal']['id'] == self.global_id
        self.user.update_setting({
          'primary_goal' => {'last_tracked' => [self.user.settings['primary_goal']['last_tracked'] || '0', iso8601].max}
        })
      end
    end
  end
    
  
  def primary?
    !!(self.user && self.user.settings && self.user.settings['primary_goal'] && self.user.settings['primary_goal']['id'] == self.global_id)
  end
  
  def badged?
    !!(self.settings && self.settings['badges'])
  end
  
  def badge_level(level)
    self.settings && self.settings['badges'] && self.settings['badges'][level - 1]
  end
  
  def process_params(params, non_user_params)
    raise "user required as goal target" unless self.user_id || non_user_params[:user]
    raise "user required as update author" unless non_user_params[:author]
    self.user ||= non_user_params[:user] if non_user_params[:user]
    self.settings ||= {}
    self.settings['author_id'] ||= non_user_params[:author].global_id
    self.active = !!params[:active] if params[:active] != nil
    self.global = !!params[:global] if params[:global] != nil
    self.settings['summary'] = process_string(params['summary']) if params['summary']
    self.settings['description'] = process_html(params['description']) if params['description']
    self.template = !!params['template'] if params['template'] != nil
    self.template_header = !!params['template_header'] if params['template_header'] && self.template_header == nil
    self.settings['badge_name']  = params['badge_name'] if params['badge_name']
    badges = UserBadge.process_goal_badges(params['badges'], params['assessment_badge']) if params['badges'] || params['assessment_badge']
    self.settings['badges'] = badges.select{|b| b['level']} if badges
    self.settings['assessment_badge'] = badges.detect{|b| b['assessment'] } if badges
    if self.template_header
      self.template = true
      self.settings['template_header_id'] ||= 'self'
    end
    if self.template
      self.settings['sequence_summary'] = process_string(params['sequence_summary']) if params['sequence_summary']
      self.settings['sequence_description'] = process_html(params['sequence_description']) if params['sequence_description']
      if params['template_header_id'] && params['template_header_id'] != self.settings['template_header_id']
        header = UserGoal.find_by_path(params['template_header_id'])
        if header && header.allows?(self.user, 'edit')
          self.settings['template_header_id'] = header.global_id
        end
      end
      if params['next_template_id'] && params['next_template_id'] != self.settings['next_template_id']
        next_template = UserGoal.find_by_path(params['next_template_id'])
        if next_template && params['next_template_id'] != self.settings['next_template_id'] && next_template.settings['template_header_id'] == self.settings['template_header_id']
          self.settings['next_template_id'] = next_template.global_id
        elsif params['next_template_id'] == ''
          self.settings['next_template_id'] = nil
        end
      end
      if params['advancement']
        parts = params['advancement'].split(/:/);
        if parts[0] == 'none'
          self.settings['goal_advances_at'] = nil
          self.settings['goal_duration'] = nil
        elsif parts[0] == 'date'
          self.settings['goal_advances_at'] = parts[1].strip
          self.settings['goal_duration'] = nil
        elsif parts[0] == 'duration'
          self.settings['goal_advances_at'] = nil
          num = [parts[1].strip.to_i, 1].max
          duration = num.days
          if parts[2] == 'month'
            duration = num.months
          elsif parts[2] == 'week'
            duration = num.weeks
          end
          self.settings['goal_duration'] = duration.to_i
        end
      end
    end
    if params['video_id']
      video = UserVideo.find_by_global_id(params['video_id'])
      if video
        self.settings['video'] = {
          'id' => params['video_id'],
          'duration' => video.settings['duration']
        }
      end
    end
    if params['template_id']
      template = UserGoal.find_by_global_id(params['template_id'])
      if template && template.template
        self.build_from_template(template, self.user)
      end
    end
    if params['comment']
      self.settings['comments'] ||= []
      self.settings['last_comment_id'] ||= 0
      video = UserVideo.find_by_global_id(params['comment']['video_id']) if params['comment']['video_id']
      comment = {
        'id' => self.settings['last_comment_id'],
        'user_id' => non_user_params[:author].global_id,
        'user_name' => non_user_params[:author].user_name,
        'created' => Time.now.iso8601,
        'text' => process_string(params['comment']['text'])
      }
      self.settings['last_comment_id'] += 1
      if video
        comment['video'] = {
          'id' => video.global_id,
          'duration' => video.settings['duration']
        }
      end
      self.settings['comments'] << comment
    end
    
    if params[:primary]
      @set_as_primary = true
      @clear_primary = false
    elsif self.primary && params[:primary] == false
      @clear_primary = true
      @set_as_primary = false
    end
    self.primary = !!params[:primary] if params[:primary] != nil
    true
  end
  
  def author
    self.settings && self.settings['author_id'] && User.find_by_global_id(self.settings['author_id'])
  end
  
  def self.current_date_from_template(str)
    return nil unless str
    res = Time.parse(str) rescue nil
    res += 1.year if res && res < Time.now && !str.match(/\d\d\d\d/)
    res
  end

  def calculate_advancement     
    if self.settings['goal_duration']
      Time.now + self.settings['goal_duration']
    elsif self.settings['goal_advances_at']
      self.goal_advance
      self.class.current_date_from_template(self.settings['goal_advances_at'])
    else
      nil
    end
  end
  
  def goal_start
    if self.settings && self.settings['goal_starts_at']
      @goal_start = self.class.current_date_from_template(self.settings['goal_starts_at'])
    else
      nil
    end
  end
  
  def goal_advance
    if self.settings && self.settings['goal_advances_at']
      @goal_advance = self.class.current_date_from_template(self.settings['goal_advances_at'])
    else
      nil
    end
  end
  
  def current_template
    return nil unless self.template
    return self unless self.template_header
    goals = UserGoal.find_all_by_global_id(self.settings['linked_template_ids'] || [])
    sorted_goals = goals.select{|g| g.goal_advance }.sort_by{|g| g.goal_advance }
    sorted_goals.detect{|g| g.goal_advance > Time.now }
  end
  
  def build_from_template(template, user, set_as_primary=false)
    if template.template_header && !self.settings['prior_goal_id']
      template = template.current_template || template
    end
    self.settings ||= {}
    self.settings['template_id'] = template.global_id
    self.advance_at = template.calculate_advancement
    self.user = user
    prior_goal = self.settings['prior_goal_id'] && UserGoal.find_by_global_id(self.settings['prior_goal_id'])
    self.settings['author_id'] = prior_goal && prior_goal.settings['author_id']
    self.settings['author_id'] ||= user.global_id
    self.settings['video'] = template.settings['video']
    self.settings['summary'] = nil if self.settings['summary'] == 'user goal'
    self.settings['summary'] ||= template.settings['summary']
    self.settings['description'] ||= template.settings['description']
    self.active = true
    @set_as_primary = true if set_as_primary
  end
  
  def next_template
    return nil unless self.settings && self.settings['next_template_id']
    res = UserGoal.find_by_global_id(self.settings['next_template_id'])
    res = nil unless res.template
    res
  end
  
  def self.add_log_session(log_id)
    session = LogSession.find_by_global_id(log_id)
    goal = session.goal
    if goal && goal.user_id == session.user_id
      goal.generate_stats
      goal.save
    end
  end

  def sanitize!
    if self.settings['assessment_badge']
      self.settings['assessment_badge']['words_list'].map!(&:strip).select!{|w| w.length > 0 } if self.settings['assessment_badge']['words_list']
      self.settings['assessment_badge']['parts_of_speech_list'].map!(&:strip).select!{|w| w.length > 0 } if self.settings['assessment_badge']['parts_of_speech_list']
    end
    if self.settings['badges']
      self.settings['badges'].each do |badge|
        badge['words_list'].map!(&:strip).select!{|w| w.length > 0 } if badge['words_list']
        badge['parts_of_speech_list'].map!(&:strip).select!{|w| w.length > 0 } if badge['parts_of_speech_list']
      end
    end
    self.save!
  end
  
  def advance!
    if !(self.settings || {})['template_id'] && self.active && self.advance_at && self.advance_at < Time.now
      # Co-opt advance_at to also be expire_at for one-time goals
      self.active = false
      return self.save
    end
    return true unless self.active && self.advance_at && self.advance_at < Time.now && self.settings && self.settings['template_id']
    template = UserGoal.find_by_global_id(self.settings['template_id'])
    return false unless template && template.template
    next_template = template.next_template
    if !next_template || !self.user
      # TODO: notification that goal has ended with no follow-up
    else
      new_goal = UserGoal.new(:settings => {'prior_goal_id' => self.global_id})
      new_goal.build_from_template(next_template, self.user, self.primary?)
      new_goal.save
      self.settings['next_goal_id'] = new_goal.global_id
    end
    
    self.active = false
    self.save
  end
  
  def self.advance_goals
    UserGoal.where(['advance_at < ?', Time.now]).each do |goal|
      goal.schedule(:advance!) if goal.user && goal.user.premium?
    end
  end
end
