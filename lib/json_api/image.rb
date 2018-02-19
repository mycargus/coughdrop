module JsonApi::Image
  extend JsonApi::Json
  
  TYPE_KEY = 'image'
  DEFAULT_PAGE = 25
  MAX_PAGE = 50
  
  def self.build_json(image, args={})
    json = {}
    json['id'] = image.global_id
    json['url'] = image.best_url
#    json['url'] = image.settings['cached_copy_url'] || image.settings['fallback_copy_url'] || image.url
    ['pending', 'content_type', 'width', 'height', 'source_url'].each do |key|
      json[key] = image.settings[key]
    end
    json['protected'] = !!image.protected?
    json['protected_source'] = image.settings['protected_source'] if json['protected']
    json['license'] = OBF::Utils.parse_license(image.settings['license'])
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