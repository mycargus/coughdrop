module ExtraData
  extend ActiveSupport::Concern

  def detach_extra_data(frd=false)
    if !frd
      if !skip_extra_data_process? && extra_data_too_big?
        schedule :detach_extra_data, true
      end
      return true
    end
    raise "extra_data_attribute not defined" unless self.extra_data_attribute
    if extra_data_too_big?
      # for button_sets, pull out self.data['buttons']
      # for logs, pull out self.data['events']
      self.data['extra_data_nonce'] ||= Security.nonce('extra_data_storage')
      extra_data = self.data[extra_data_attribute]
      public_extra_data = self.extra_data_public_transform(extra_data)

      if public_extra_data
        public_file = dir + "data-#{self.global_id}.json"
        # upload public access file
      end
      private_key = GoSecure.hmac(self.data['extra_data_nonce'], 'extra_data_private_key', 1)
      dir = "/extras/#{self.class.to_s}/#{self.global_id}/#{self.data['extra_data_nonce']}/"
      private_file = dir + "data-#{private_key}.json"
      # figure out a quick check to see if it's small enough to ignore
      # generate large nonce to protect
      # upload to "/extras/<global_id>/<nonce>/<global_id>.json"
      # persist the nonce and the url, remove the big-data attribute
      @skip_extra_data_update = true
      # save
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

  def extra_data_public_transform(data)
    nil
  end

  def extra_data_public_url
    return nil unless self.data['extra_data_nonce']
    dir = "/extras/#{self.class.to_s}/#{self.global_id}/#{self.data['extra_data_nonce']}/"
    "#{JsonApi::Json.current_host}#{dir}data-#{self.global_id}.json"    
  end

  def extra_data_private_url
    return nil unless self.data['extra_data_nonce']
    private_key = GoSecure.hmac(self.data['extra_data_nonce'], 'extra_data_private_key', 1)
    dir = "/extras/#{self.class.to_s}/#{self.global_id}/#{self.data['extra_data_nonce']}/"
    "#{JsonApi::Json.current_host}#{dir}data-#{private_key}.json"    
  end

  def skip_extra_data_processing?
    # don't process for any record that has the data remotely
    # but doesn't have the data locally
  end

  def extra_data_too_big?
    # default would be to stringify and check length,
    # but can be overridden to check .data['buttons'].length, etc.
  end

  def assert_extra_data
    # if big-data attribute is missing and url is defined,
    # make a remote call to retrieve the data and set it
    # to the big-data attribute (without saving)

    # TODO: start adding support to extra_data retrieval
    # directly from the client, instead of having to hold up the server request
  end

  def clear_extra_data
    # remvoe the record from the remove location
  end

  included do
#    after_save :detach_extra_data
#    after_destroy :clear_extra_data

    def clear_extra_data_orphans
      # query the remote storage, search for records in batches
      # for any record that doesn't exist, remove the storage entry
      # for any record that no longer has the URL reference, remove the storage entry
    end
  end
end

