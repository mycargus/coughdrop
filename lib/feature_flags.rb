module FeatureFlags
  AVAILABLE_FRONTEND_FEATURES = ['subscriptions', 'assessments', 'custom_sidebar', 'canvas_render']
  ENABLED_FRONTEND_FEATURES = ['subscriptions', 'assessments']
  DISABLED_CANARY_FEATURES = []
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
end