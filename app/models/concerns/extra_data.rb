module ExtraData
  extend ActiveSupport::Concern

  def detach_extra_data(frd=false)
    if !frd
      if !skip_extra_data_processing? && extra_data_too_big?
        schedule :detach_extra_data, true
      end
      return true
    end
    raise "extra_data_attribute not defined" unless self.extra_data_attribute
    if self.data['extra_data_nonce'] && !self.data[extra_data_attribute]
      self.assert_extra_data
    end
    # figure out a quick check to see if it's small enough to ignore
    if extra_data_too_big? || frd == 'force'
      # generate large nonce to protect
      self.data['extra_data_nonce'] ||= GoSecure.nonce('extra_data_storage')
      # for button_sets, pull out self.data['buttons']
      # for logs, pull out self.data['events']
      extra_data = self.data[extra_data_attribute]

      private_path, public_path = self.class.extra_data_remote_paths(self.data['extra_data_nonce'], self.global_id)
      public_extra_data = extra_data && self.class.extra_data_public_transform(extra_data)
      if public_extra_data
        self.data['extra_data_public'] = true
        file = Tempfile.new("stash")
        file.write(public_extra_data.to_json)
        file.close
        Uploader.remote_upload(public_path, file.path, 'text/json')
      end
      # upload to "/extras/<global_id>/<nonce>/<global_id>.json"
      file = Tempfile.new("stash")
      file.write(extra_data.to_json)
      file.close
      Uploader.remote_upload(private_path, file.path, 'text/json')
      # persist the nonce and the url, remove the big-data attribute
      self.data.delete(extra_data_attribute)
      @skip_extra_data_update = true
      self.save
      @skip_extra_data_update = false
    end
    true
  end
  
  def extra_data_attribute
    if self.is_a?(LogSession)
      'events'
    elsif self.is_a?(BoardDownstreamButtonSet)
      'buttons'
    else
      nil
    end
  end

  def extra_data_public_url
    return nil unless self.data && self.data['extra_data_nonce'] && self.data['extra_data_public']
    path = self.class.extra_data_remote_paths(self.data['extra_data_nonce'], self.global_id)[1]
    "#{ENV['UPLOADS_S3_CDN']}/#{path}"
  end

  def extra_data_private_url
    return nil unless self.data && self.data['extra_data_nonce']
    path = self.class.extra_data_remote_paths(self.data['extra_data_nonce'], self.global_id)[0]
    "#{ENV['UPLOADS_S3_CDN']}/#{path}"
  end

  def skip_extra_data_processing?
    # don't process for any record that has the data remotely
    # but doesn't have the data locally
    if @skip_extra_data_update
      return true
    elsif self.data && self.data['extra_data_nonce']
      return true
    end
    false
  end

  def extra_data_too_big?
    if self.is_a?(LogSession)
      user = self.user
      if user && user.settings['extra_data_test'] && self.data['events'] && self.data['events'].length > 5
        return true
      end
    end
    # default would be to stringify and check length,
    # but can be overridden to check .data['buttons'].length, etc.
    false
  end

  def assert_extra_data
    # if big-data attribute is missing and url is defined,
    # make a remote call to retrieve the data and set it
    # to the big-data attribute (without saving)

    # TODO: start adding support to extra_data retrieval
    # directly from the client, instead of having to hold up the server request
    url = self.extra_data_private_url
    if url
      req = Typhoeus.get(url)
      data = JSON.parse(req.body)
      self.data[self.extra_data_attribute] = data
    end
  end

  def clear_extra_data
    if self.data && self.data['extra_data_nonce']
      self.class.schedule(:clear_extra_data, self.data['extra_data_nonce'], self.global_id)
    end
    true
  end

  included do
    after_save :detach_extra_data
    after_destroy :clear_extra_data
  end

  module ClassMethods
    def clear_extra_data_orphans
      # query the remote storage, search for records in batches
      # for any record that doesn't exist, remove the storage entry
      # for any record that no longer has the URL reference, remove the storage entry
    end

    def extra_data_public_transform(data)
      nil
    end
  
    def extra_data_remote_paths(nonce, global_id)
      private_key = GoSecure.hmac(nonce, 'extra_data_private_key', 1)
      dir = "/extras/#{self.to_s}/#{global_id}/#{nonce}/"
      public_path = dir + "data-#{global_id}.json"
      private_path = dir + "data-#{private_key}.json"
      [private_path, public_path]
    end

    def clear_extra_data(nonce, global_id)
      private_path, public_path = extra_data_remote_paths(nonce, global_id)
      Uploader.remote_remove(private_path)
      Uploader.remote_remove(public_path)
      # remove them both
    end
  end
end

