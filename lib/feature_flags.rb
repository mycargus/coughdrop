module FeatureFlags
  AVAILABLE_FRONTEND_FEATURES = ['subscriptions', 'assessments', 'custom_sidebar', 
              'canvas_render', 'snapshots', 'enable_all_buttons', 'chrome_filesystem',
              'video_recording', 'goals', 'app_connections', 'translation', 'geo_sidebar',
              'modeling', 'edit_before_copying', 'core_reports', 'lessonpix',
              'audio_recordings']
  ENABLED_FRONTEND_FEATURES = ['subscriptions', 'assessments', 'custom_sidebar', 'snapshots',
              'video_recording', 'goals', 'modeling', 'geo_sidebar']
  DISABLED_CANARY_FEATURES = []
  FEATURE_DATES = {
    'word_suggestion_images' => 'Jan 21, 2017',
    'hidden_buttons' => 'Feb 2, 2017',
    'browser_no_autosync' => 'Feb 22, 2017'
  }
  def self.frontend_flags_for(user)
    flags = {}
    AVAILABLE_FRONTEND_FEATURES.each do |feature|
      if ENABLED_FRONTEND_FEATURES.include?(feature)
        flags[feature] = true
      elsif user && user.settings && user.settings['feature_flags'] && user.settings['feature_flags'][feature]
        flags[feature] = true
      elsif user && user.settings && user.settings['feature_flags'] && user.settings['feature_flags']['canary'] && !DISABLED_CANARY_FEATURES.include?(feature)
        flags[feature] = true
      end
    end
    flags
  end
  
  def self.user_created_after?(user, feature)
    return false unless FEATURE_DATES[feature]
    date = Date.parse(FEATURE_DATES[feature]) rescue Date.today
    created = (user.created_at || Time.now).to_date
    return !!(created >= date)
  end
  
  def self.feature_enabled_for?(feature, user)
    flags = frontend_flags_for(user)
    !!flags[feature]
  end
end