module FeatureFlags
  AVAILABLE_FRONTEND_FEATURES = ['subscriptions', 'assessments', 'custom_sidebar', 
              'canvas_render', 'snapshots', 'enable_all_buttons', 
              'video_recording', 'goals', 'app_connections', 'translation', 'geo_sidebar',
              'modeling', 'edit_before_copying', 'core_reports', 'lessonpix',
              'audio_recordings', 'fast_render', 'badge_progress', 'board_levels', 'premium_symbols',
              'find_multiple_buttons']
  ENABLED_FRONTEND_FEATURES = ['subscriptions', 'assessments', 'custom_sidebar', 'snapshots',
              'video_recording', 'goals', 'modeling', 'geo_sidebar', 'edit_before_copying',
              'core_reports', 'lessonpix', 'translation', 'fast_render',
              'audio_recordings', 'app_connections', 'enable_all_buttons', 'badge_progress',
              'premium_symbols', 'board_levels']
  DISABLED_CANARY_FEATURES = []
  FEATURE_DATES = {
    'word_suggestion_images' => 'Jan 21, 2017',
    'hidden_buttons' => 'Feb 2, 2017',
    'browser_no_autosync' => 'Feb 22, 2017',
    'folder_icons' => 'Mar 7, 2017',
    'symbol_background' => 'May 10, 2017',
    'new_index' => 'Feb 17, 2018'
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