require 's3'
module Uploader
  S3_EXPIRATION_TIME=60*60
  CONTENT_LENGTH_RANGE=200.megabytes.to_i
  
  def self.remote_upload(remote_path, local_path, content_type)
    params = remote_upload_params(remote_path, content_type)
    post_params = params[:upload_params]
    return nil unless File.exist?(local_path)
    post_params[:file] = File.open(local_path, 'rb')

    # upload to s3 from tempfile
    res = Typhoeus.post(params[:upload_url], body: post_params)
    if res.success?
      return params[:upload_url] + remote_path
    else
      raise res.body
      return nil
    end
  end
  
  def self.check_existing_upload(remote_path)
    return nil
    # TODO: if the path exists and won't expire for at least 48 hours
    # then return the existing record URL
  end

  def self.remote_remove(url)
    remote_path = url.sub(/^https:\/\/#{ENV['UPLOADS_S3_BUCKET']}\.s3\.amazonaws\.com\//, '')
    remote_path = remote_path.sub(/^https:\/\/s3\.amazonaws\.com\/#{ENV['UPLOADS_S3_BUCKET']}\//, '')
    remote_path = remote_path.sub(/^#{ENV['UPLOADS_S3_CDN']}/, '')

    raise "scary delete, not a path I'm comfortable deleting..." unless remote_path.match(/\w+\/.+\/\w+-\w+(\.\w+)?$/)
    config = remote_upload_config
    service = S3::Service.new(:access_key_id => config[:access_key], :secret_access_key => config[:secret])
    bucket = service.buckets.find(config[:bucket_name])
    object = bucket.objects.find(remote_path) rescue nil
    object.destroy if object
  end
  
  def self.fronted_url(url)
    return nil unless url
    maps = [[ENV['UPLOADS_S3_BUCKET'], ENV['UPLOADS_S3_CDN']], [ENV['OPENSYMBOLS_S3_BUCKET'], ENV['OPENSYMBOLS_S3_CDN']]]
    maps.each do |bucket, cdn|
      if bucket && url.match(/^https:\/\/#{bucket}\.s3\.amazonaws\.com\//) && cdn
        url = url.sub(/^https:\/\/#{bucket}\.s3\.amazonaws\.com\//, cdn + "/")
      elsif bucket && url.match(/^https:\/\/s3\.amazonaws\.com\/#{bucket}\//) && cdn
        url= url.sub(/^https:\/\/s3\.amazonaws\.com\/#{bucket}\//, cdn + "/")
      end
    end
    url
  end
  
  def self.signed_download_url(url)
    remote_path = url.sub(/^https:\/\/#{ENV['STATIC_S3_BUCKET']}\.s3\.amazonaws\.com\//, '')
    remote_path = remote_path.sub(/^https:\/\/s3\.amazonaws\.com\/#{ENV['STATIC_S3_BUCKET']}\//, '')

    config = remote_upload_config
    service = S3::Service.new(:access_key_id => config[:access_key], :secret_access_key => config[:secret])
    bucket = service.buckets.find(config[:static_bucket_name])
    object = bucket.objects.find(remote_path) rescue nil
    if object
      object.temporary_url
    else
      nil
    end
  end
  
  def self.remote_upload_params(remote_path, content_type)
    config = remote_upload_config
    
    res = {
      :upload_url => config[:upload_url],
      :upload_params => {
        'AWSAccessKeyId' => config[:access_key]
      }
    }
    
    policy = {
      'expiration' => (S3_EXPIRATION_TIME).seconds.from_now.utc.iso8601,
      'conditions' => [
        {'key' => remote_path},
        {'acl' => 'public-read'},
        ['content-length-range', 1, (CONTENT_LENGTH_RANGE)],
        {'bucket' => config[:bucket_name]},
        {'success_action_status' => '200'},
        {'content-type' => content_type}
      ]
    }
    # TODO: for pdfs, policy['conditions'] << {'content-disposition' => 'inline'}

    policy_encoded = Base64.encode64(policy.to_json).gsub(/\n/, '')
    signature = Base64.encode64(
      OpenSSL::HMAC.digest(
        OpenSSL::Digest.new('sha1'), config[:secret], policy_encoded
      )
    ).gsub(/\n/, '')

    res[:upload_params].merge!({
       'key' => remote_path,
       'acl' => 'public-read',
       'policy' => policy_encoded,
       'signature' => signature,
       'Content-Type' => content_type,
       'success_action_status' => '200'
    })
    res
  end
  
  def self.remote_upload_config
    @remote_upload_config ||= {
      :upload_url => "https://#{ENV['UPLOADS_S3_BUCKET']}.s3.amazonaws.com/",
      :access_key => ENV['AWS_KEY'],
      :secret => ENV['AWS_SECRET'],
      :bucket_name => ENV['UPLOADS_S3_BUCKET'],
      :static_bucket_name => ENV['STATIC_S3_BUCKET']
    }
  end
  
  def self.remote_zip(url, &block)
    result = []
    Progress.update_current_progress(0.1, :downloading_file)
    response = Typhoeus.get(url)
    Progress.update_current_progress(0.2, :processing_file)
    file = Tempfile.new('stash')
    file.binmode
    file.write response.body
    file.close
    OBF::Utils.load_zip(file.path) do |zipper|
      Progress.as_percent(0.2, 1.0) do
        block.call(zipper)
      end
    end
    file.unlink
  end
  
  def self.generate_zip(urls, filename)
    Progress.update_current_progress(0.2, :checking_files)
    path = OBF::Utils.temp_path("stash")

    content_type = 'application/zip'
    
    hash = Digest::MD5.hexdigest(urls.to_json)
    key = GoSecure.sha512(hash, 'url_list')
    remote_path = "downloads/#{key}/#{filename}"
    url = Uploader.check_existing_upload(remote_path)
    return url if url
    Progress.update_current_progress(0.3, :zipping_files)
    
    Progress.as_percent(0.3, 0.8) do
      OBF::Utils.build_zip(path) do |zipper|
        urls.each_with_index do |ref, idx|
          if ref['url']
            # download the file
            fetch = OBF::Utils.get_url(ref['url'])
            url_filename = ref['name']
            # add it to the zip
            zipper.add(url_filename, fetch['data'])
          elsif ref['data']
            zipper.add(ref['name'], ref['data'])
          end
          Progress.update_current_progress(idx.to_f / urls.length.to_f)
        end
      end
    end
    Progress.update_current_progress(0.9, :uploading_file)
    url = Uploader.remote_upload(remote_path, path, content_type)
    raise "File not uploaded" unless url
    File.unlink(path) if File.exist?(path)
    return url
  end
  
  def self.valid_remote_url?(url)
    # TODO: this means we can never delete files from the bucket... is that ok?
    res = self.removable_remote_url?(url)
    # don't re-download files that have already been downloaded
    res ||= url.match(/^https:\/\/#{ENV['OPENSYMBOLS_S3_BUCKET']}\.s3\.amazonaws\.com\//) if ENV['OPENSYMBOLS_S3_BUCKET']
    res ||= url.match(/^https:\/\/s3\.amazonaws\.com\/#{ENV['OPENSYMBOLS_S3_BUCKET']}\//) if ENV['OPENSYMBOLS_S3_BUCKET']
    res ||= url.match(/^#{ENV['OPENSYMBOLS_S3_CDN']}\//) if ENV['OPENSYMBOLS_S3_CDN']
    res ||= protected_remote_url?(url)
    !!res
  end
  
  def self.protected_remote_url?(url)
    !!(url && url.match(/\/api\/v\d+\/users\/.+\/protected_image/))
  end
  
  def self.removable_remote_url?(url)
    res = url.match(/^https:\/\/#{ENV['UPLOADS_S3_BUCKET']}\.s3\.amazonaws\.com\//)
    res ||= url.match(/^https:\/\/s3\.amazonaws\.com\/#{ENV['UPLOADS_S3_BUCKET']}\//)
    !!res
  end
  
  def self.lessonpix_credentials(opts)
    return nil unless ENV['LESSONPIX_PID'] && ENV['LESSONPIX_SECRET']
    username = nil
    password_md5 = nil
    if opts.is_a?(User)
      template = UserIntegration.find_by(template: true, integration_key: 'lessonpix')
      ui = template && UserIntegration.find_by(user: opts, template_integration: template)
      return nil unless ui && ui.settings && ui.settings['user_settings'] && ui.settings['user_settings']['username']
      username = ui.settings['user_settings']['username']['value']
      password_md5 = GoSecure.decrypt(ui.settings['user_settings']['password']['value_crypt'], ui.settings['user_settings']['password']['salt'], 'integration_password')
    elsif opts.is_a?(UserIntegration)
      username = opts.settings['user_settings']['username']['value']
      password_md5 = GoSecure.decrypt(opts.settings['user_settings']['password']['value_crypt'], opts.settings['user_settings']['password']['salt'], 'integration_password')
    elsif opts.is_a?(Hash)
      username = opts['username']
      password_md5 = Digest::MD5.hexdigest((opts['password'] || '').downcase)
    else
      return nil
    end
    {
      'pid' => ENV['LESSONPIX_PID'],
      'username' => username,
      'token' => Digest::MD5.hexdigest(password_md5 + ENV['LESSONPIX_SECRET'])
    }
  end
  
  def self.found_image_url(image_id, library, user)
    if library == 'lessonpix'
      cred = lessonpix_credentials(user)
      return nil unless cred
      url = "https://lessonpix.com/apiGetImage.php?pid=#{cred['pid']}&username=#{cred['username']}&token=#{cred['token']}&image_id=#{image_id}&h=300&w=300&fmt=png"
    else
      return nil
    end
  end
  
  def self.fallback_image_url(image_id, library)
    if library == 'lessonpix'
      return "https://lessonpix.com/drawings/#{image_id}/100x100/#{image_id}.png"
    else
      return nil
    end
  end
  
  def self.find_images(keyword, library, user)
    return false if (keyword || '').strip.blank? || (library || '').strip.blank?
    if library == 'ss'
      return false
    elsif library == 'lessonpix'
      cred = lessonpix_credentials(user)
      return false unless cred
      url = "http://lessonpix.com/apiKWSearch.php?pid=#{cred['pid']}&username=#{cred['username']}&token=#{cred['token']}&word=#{CGI.escape(keyword)}&fmt=json&allstyles=n&limit=30"
      req = Typhoeus.get(url)
      return false if req.body && (req.body.match(/Token Mismatch/) || req.body.match(/Unkonwn User/) || req.body.match(/Unknown User/))
      results = JSON.parse(req.body) rescue nil
      list = []
      results.each do |obj|
        next if !obj || obj['iscategory'] == 't'
        list << {
          'url' => "#{JsonApi::Json.current_host}/api/v1/users/#{user.global_id}/protected_image/lessonpix/#{obj['image_id']}",
          'thumbnail_url' => self.fallback_image_url(obj['image_id'], 'lessonpix'),
          'content_type' => 'image/png',
          'name' => obj['title'],
          'width' => 300,
          'height' => 300,
          'external_id' => obj['image_id'],
          'public' => false,
          'protected' => true,
          'license' => {
            'type' => 'private',
            'source_url' => "http://lessonpix.com/pictures/#{obj['image_id']}/#{CGI.escape(obj['title'] || '')}",
            'author_name' => 'LessonPix',
            'author_url' => 'http://lessonpix.com',
            'uneditable' => true,
            'copyright_notice_url' => 'http://lessonpix.com/articles/11/28/LessonPix+Terms+and+Conditions'
          }          
        }
      end
      Worker.schedule_for(:slow, ButtonImage, :perform_action, {
        'method' => 'assert_cached_copies',
        'arguments' => [list.map{|r| r['url'] }]
      })
      return list
    elsif ['pixabay_vectors', 'pixabay_photos'].include?(library)
      type = library.match(/vector/) ? 'vector' : 'photo'
      key = ENV['PIXABAY_KEY']
      return false unless key
      url = "https://pixabay.com/api/?key=#{key}&q=#{CGI.escape(keyword)}&image_type=#{type}&per_page=30&safesearch=true"
      req = Typhoeus.get(url, :ssl_verifypeer => false)
      results = JSON.parse(req.body) rescue nil
      return [] unless results && results['hits']
      list = []
      results['hits'].each do |obj|
        ext = obj['webformatURL'].split(/\./)[-1]
        type = MIME::Types.type_for(ext)[0]
        list << {
          'url' => obj['webformatURL'],
          'thumbnail_url' => obj['previewURL'] || obj['webformatURL'],
          'content_type' => (type && type.content_type) || 'image/jpeg',
          'width' => obj['webformatWidth'],
          'height' => obj['webformatHeight'],
          'external_id' => obj['id'],
          'public' => true,
          'license' => {
            'type' => 'public_domain',
            'copyright_notice_url' => 'https://creativecommons.org/publicdomain/zero/1.0/',
            'source_url' => obj['pageURL'],
            'author_name' => 'unknown',
            'author_url' => 'https://creativecommons.org/publicdomain/zero/1.0/',
            'uneditable' => true
          }          
        }
      end
      return list
    elsif ['giphy_asl'].include?(library)
      str = "#asl #{keyword}"
      key = ENV['GIPHY_KEY']
      res = Typhoeus.get("http://api.giphy.com/v1/gifs/search?q=#{CGI.escape(str)}&api_key=#{key}")
      results = JSON.parse(res.body)
      list = []
      results['data'].each do |result|
        if result['slug'].match(/signwithrobert/) || result['slug'].match(/asl/)
          list << {
            'url' => (result['images']['original']['url'] || '').sub(/^http:/, 'https:'),
            'thumbnail_url' => (result['images']['downsized_still']['url'] || '').sub(/^http:/, 'https:'),
            'content_type' => 'image/gif',
            'width' => result['images']['original']['width'].to_i,
            'height' => result['images']['original']['height'].to_i,
            'public' => false,
            'license' => {
              'type' => 'private',
              'copyright_notice_url' => 'https://giphy.com/terms',
              'source_url' => result['url'],
              'author_name' => result['username'],
              'author_url' => result['user'] && result['user']['profile_url'],
              'uneditable' => true
            }
          }
        end
      end
      return list
    elsif ['noun-project', 'sclera', 'arasaac', 'mulberry', 'tawasol', 'twemoji'].include?(library)
      str = "#{keyword} repo:#{library}"
      res = Typhoeus.get("https://www.opensymbols.org/api/v1/symbols/search?q=#{CGI.escape(str)}", :ssl_verifypeer => false)
      results = JSON.parse(res.body)
      results.each do |result|
        if result['extension']
          type = MIME::Types.type_for(result['extension'])[0]
          result['content_type'] = type.content_type
        end
      end
      return [] if results.empty?
      list = []
      results.each do |obj|
        list << {
          'url' => obj['image_url'],
          'thumbnail_url' => obj['image_url'],
          'content_type' => obj['content_type'],
          'width' => obj['width'],
          'height' => obj['height'],
          'external_id' => obj['id'],
          'public' => true,
          'license' => {
            'type' => obj['license'],
            'copyright_notice_url' => obj['license_url'],
            'source_url' => obj['source_url'],
            'author_name' => obj['author'],
            'author_url' => obj['author_url'],
            'uneditable' => true
          }
        }        
      end
      return list
    end
    return false
  end
  
  def self.find_resources(query, source, user)
    tarheel_prefix = "https://tarheelreader.org" #ENV['TARHEEL_PROXY'] || "https://images.weserv.nl/?url=tarheelreader.org"
    if source == 'tarheel'
      url = "https://tarheelreader.org/find/?search=#{CGI.escape(query)}&category=&reviewed=R&audience=E&language=en&page=1&json=1"
      res = Typhoeus.get(url)
      results = JSON.parse(res.body)
      list = []
      results['books'].each do |book|
        list << {
          'url' => "https://tarheelreader.org#{book['link']}",
          'image' => tarheel_prefix + book['cover']['url'],
          'title' => book['title'],
          'author' => book['author'],
          'id' => book['slug'],
          'image_attribution' => "https://tarheelreader.org/photo-credits/?id=#{book['ID']}"
        }
      end
      return list
    elsif source == 'tarheel_book'
      url = "https://tarheelreader.org/book-as-json/?slug=#{CGI.escape(query)}"
      if query.match(/^http/)
        url = query
      end
      results = AccessibleBooks.find_json(url)
      list = []
      results['pages'].each_with_index do |page, idx|
        list << {
          'id' => page['id'] || "#{results['slug']}-#{idx}",
          'title' => page['text'],
          'image' => page['image_url'] || (tarheel_prefix + page['url']),
          'image_content_type' => page['image_content_type'] || 'image/jpeg',
          'url' => results['book_url'] || "https://tarheelreader.org#{results['link']}",
          'image_attribution' => page['image_attribution_url'] || "https://tarheelreader.org/photo-credits/?id=#{results['ID']}",
          'image_author' => page['image_attribution_author'] || 'Flickr User'
        }
      end
      return list
    end
    []
  end
end
