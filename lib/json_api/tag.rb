module JsonApi::Tag
  extend JsonApi::Json
  
  TYPE_KEY = 'tag'
  DEFAULT_PAGE = 10
  MAX_PAGE = 25
    
  def self.build_json(tag, args={})
    json = {}
    
    json['id'] = tag.global_id
    json['tag_id'] = tag.tag_id
    json['public'] = tag.public
    if tag.data['button']
      json['button'] = tag.data['button']
    else
      json['label'] = tag.data['label']
    end
    json
  end
end
