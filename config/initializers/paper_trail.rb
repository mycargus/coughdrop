# PaperTrail.config.track_associations = false
PaperTrail.serializer = GoSecure::SecureJson

module PaperTrail::VersionConcern
  def reify
    self.item_type.constantize.load_version(self)
  end
end

module PaperTrail
  def self.whodunnit
    PaperTrail.request.whodunnit
  end

  def self.whodunnit=(usr)
    PaperTrail.request.whodunnit = usr
  end
end
