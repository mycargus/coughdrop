PaperTrail.config.track_associations = false
PaperTrail.serializer = SecureJson

module PaperTrail::VersionConcern
  def reify
    self.item_type.constantize.load_version(self)
  end
end

# DEPRECATION WARNING: PaperTrail.track_associations has not been set. As of PaperTrail 5, it defaults to false. Tracking associations is an experimental feature so we recommend setting PaperTrail.config.track_associations = false in your config/initializers/paper_trail.rb  (called from run_on_shard at /Users/whitmer/.rvm/gems/ruby-2.3.3/bundler/gems/octopus-578be91af8be/lib/octopus/shard_tracking.rb:41)
