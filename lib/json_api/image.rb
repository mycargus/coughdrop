module JsonApi::Image
  extend JsonApi::Json
  
  TYPE_KEY = 'image'
  DEFAULT_PAGE = 25
  MAX_PAGE = 50
  
  def self.build_json(image, args={})
    json = {}
    json['id'] = image.global_id
    json['url'] = image.best_url
    settings = image.settings
    settings['protected_source'] ||= 'lessonpix' if settings['license'] && settings['license']['source_url'] && settings['license']['source_url'].match(/lessonpix/)
    protected_source = !!image.protected?
    allowed_sources = args[:allowed_sources]
    allowed_sources ||= args[:permissions] && args[:permissions].enabled_protected_sources
    allowed_sources ||= []
    if settings && protected_source && !allowed_sources.include?(settings['protected_source'])
      settings = settings['fallback'] || {}
      json['url'] = Uploader.fronted_url(settings['url'])
      json['fallback'] = true
      protected_source = false
    end
    ['pending', 'content_type', 'width', 'height', 'source_url'].each do |key|
      json[key] = settings[key]
    end
    json['protected'] = protected_source
    json['protected_source'] = settings['protected_source'] if json['protected']
    json['license'] = OBF::Utils.parse_license(settings['license'])
    if (args[:data] || !image.url) && image.data
      json['url'] = image.data
    end
    if args[:permissions]
      json['permissions'] = image.permissions_for(args[:permissions])
    end
    json
  end
  
  def self.meta(image)
    json = {}
    if image.pending_upload?
      params = image.remote_upload_params
      json = {'remote_upload' => params}
    end
    json
  end
end