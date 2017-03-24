require 'mime/types'

module Uploadable
  extend ActiveSupport::Concern
  
  def file_type 
    if self.is_a?(ButtonImage)
      'images'
    elsif self.is_a?(ButtonSound)
      'sounds'
    elsif self.is_a?(UserVideo)
      'videos'
    else
      'objects'
    end
  end
  
  def confirmation_key
    Security.sha512(self.global_id + self.class.to_s, 'uploadable_file')
  end
  
  def full_filename
    return self.settings['full_filename'] if self.settings['full_filename']
    extension = ""
    type = MIME::Types[self.content_type]
    type = type && type[0]
    extension = ("." + type.extensions.first) if type && type.extensions && type.extensions.length > 0
    self.settings['full_filename'] = self.file_path + self.file_prefix + extension
    self.save
    self.settings['full_filename']
  end
  
  def url_for(user)
    token = user && user.user_token
    return self.url if !token
    return self.url unless self.url.match(/\/api\/v1\/users\/.+\/protected_image/)
    self.url + (self.url.match(/\?/) ? '&' : '?') + "user_token=#{token}"
  end
  
  def file_prefix
    sha = Security.sha512(self.global_id, self.created_at.iso8601)
    self.global_id + "-" + sha
  end
  
  def file_path
    digits = self.id.to_s.split(//)
    self.file_type + "/" + digits.join("/") + "/"
  end
  
  def content_type
    self.settings['content_type'] || raise("content type required for uploads")
  end
  
  def pending_upload?
    !!self.settings['pending']
  end
  
  def process_url(url, non_user_params)
    already_stored = Uploader.valid_remote_url?(url)
    if already_stored || non_user_params[:download] == false
      self.url = url
    else
      self.settings['pending_url'] = url
    end
    @remote_upload_possible = non_user_params[:remote_upload_possible]
    url
  end
  
  def check_for_pending
    self.settings ||= {}
    self.settings['pending'] = !!(!self.url || self.settings['pending_url'])
    
    # If there's no client to handle remote upload, go ahead and unmark it as
    # pending and schedule a bg job to download server-side
    if !@remote_upload_possible && self.settings['pending'] && self.settings['pending_url']
      self.settings['pending'] = false
      self.url = self.settings['pending_url']
      @schedule_upload_to_remote = true
    end
    # TODO: check if it's a protected image (i.e. lessonpix) and download a cached
    # copy according. Keep the link pointing to our API for permission checks,
    # but store somewhere and allow for redirects
    true
  end
  
  def check_for_removable
    if self.url && Uploader.removable_remote_url?(self.url)
      self.removable = true
    end
    true
  end
  
  def schedule_remote_removal_if_unique
    if self.url && self.removable
      if self.class.where(:url => self.url).count == 0
        Worker.schedule(Uploader, :remote_remove, self.url)
        true
      end
    end
    false
  end
    
  def upload_after_save
    if @schedule_upload_to_remote
      self.schedule(:upload_to_remote, self.settings['pending_url'])
      @schedule_upload_to_remote = false
    end
    if self.url && Uploader.protected_remote_url?(self.url)
      self.schedule(:assert_cached_copy)
    end
    true
  end
  
  def assert_cached_copy
    if self.url && Uploader.protected_remote_url?(self.url)
      ref = self.class.cached_copy_identifiers(self.url)
      return false unless ref
      bi = ButtonImage.find_by_url(ref[:url])
      if self.settings['copy_attempts'] && self.settings['copy_attempts'] > 2
        return false
      end
      if !bi
        user = User.find_by_path(ref[:user_id])
        remote_url = Uploader.found_image_url(ref[:image_id], ref[:library], user)
        if remote_url
          bi = ButtonImage.create(url: ref[:url], public: false)
          bi.upload_to_remote(remote_url)
          if bi.settings['errored_pending_url']
            bi.destroy
            self.settings['copy_attempts'] = (self.settings['copy_attempts'] || 0) + 1
            self.save
            self.schedule(:assert_cached_copy)
            return false
          else
            bi.settings['cached_copy_url'] = remote_url
            bi.url = ref[:url]
            bi.save
            return true
          end
        else
          return false
        end
      else
        return true
      end
    else
      false
    end
  end
  
  def remote_upload_params
    res = Uploader.remote_upload_params(self.full_filename, self.content_type)
    res[:success_url] = "#{JsonApi::Json.current_host}/api/v1/#{self.file_type}/#{self.global_id}/upload_success?confirmation=#{self.confirmation_key}"
    res  
  end
  
  def upload_to_remote(url)
    raise "must have id first" unless self.id
    self.settings['pending_url'] = nil
    url = self.settings['data_uri'] if url == 'data_uri'
    file = Tempfile.new("stash")
    file.binmode
    if url.match(/^data:/)
      self.settings['content_type'] = url.split(/;/)[0].split(/:/)[1]
      data = url.split(/,/)[1]
      file.write(Base64.strict_decode64(data))
    else
      self.settings['source_url'] = url
      res = Typhoeus.get(URI.escape(url))
      # TODO: regex depending on self.file_type
      re = /^audio/
      re = /^image/ if file_type == 'images'
      re = /^video/ if file_type == 'videos'
      if res.success? && res.headers['Content-Type'].match(re)
        self.settings['content_type'] = res.headers['Content-Type']
        file.write(res.body)

        if file_type == 'images' && !self.settings['width']
          identify_data = `identify -verbose #{file.path}`
          identify_data.split(/\n/).each do |line|
            pre, post = line.sub(/^\s+/, '').split(/:\s/, 2)
            if pre == 'Geometry'
              match = (post || "").match(/(\d+)x(\d+)/)
              if match && match[1] && match[2]
                self.settings['width'] = match[1].to_i
                self.settings['height'] = match[2].to_i
              end
            end
          end
        end
      else
        self.settings['errored_pending_url'] = url
        self.save
        return
      end
    end
    file.rewind
    params = self.remote_upload_params
    post_params = params[:upload_params]
    post_params[:file] = file

    # upload to s3 from tempfile
    res = Typhoeus.post(params[:upload_url], body: post_params)
    if res.success?
      self.url = params[:upload_url] + self.full_filename
      self.settings['pending'] = false
      self.settings['data_uri'] = nil
      self.settings['pending_url'] = nil
      self.save
    else
      self.settings['errored_pending_url'] = url
      self.save
    end
  end

  module ClassMethods  
    def cached_copy_url(url, user)
      if url && Uploader.protected_remote_url?(url)
        ref = self.cached_copy_identifiers(url)
        if ref[:library] == 'lessonpix'
          return nil unless user && Uploader.lessonpix_credentials(user)
        else
          return nil
        end
        bi = ButtonImage.find_by_url(ref[:url])
        return bi && bi.settings['cached_copy_url']
      else
        nil
      end
    end

    def cached_copy_identifiers(url)
      return nil unless url
      parts = url.match(/api\/v\d+\/users\/([^\/]+)\/protected_image\/(\w+)\/(\w+)/)
      if parts && parts[1] && parts[2] && parts[3]
        res = {
          user_id: parts[1],
          library: parts[2],
          image_id: parts[3],
          url: "coughdrop://protected_image/#{parts[2]}/#{parts[3]}"
        }
        return res
      end
      nil
    end
  end
  
  included do
    before_save :check_for_pending
    before_save :check_for_removable
    after_save :upload_after_save
    after_destroy :schedule_remote_removal_if_unique
  end
end
