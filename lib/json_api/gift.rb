module JsonApi::Gift
  extend JsonApi::Json
  
  TYPE_KEY = 'gift'
  DEFAULT_PAGE = 25
  MAX_PAGE = 50
    
  def self.build_json(gift, args={})
    json = {}
    json['id'] = gift.code
    json['created'] = gift.created_at.iso8601
    json['code'] = gift.code
    json['duration'] = gift.duration
    json['seconds'] = gift.settings['seconds_to_add'].to_i
    json['licenses'] = gift.settings['licenses']
    json['active'] = gift.active
    json['purchased'] = gift.purchased?
    json['organization'] = gift.settings['organization']
    json['gift_name'] = gift.settings['gift_name']
    json['email'] = gift.settings['email'] if json['organization']
    json['amount'] = gift.settings['amount']
    json['memo'] = gift.settings['memo']
    
    if args[:permissions]
      json['permissions'] = gift.permissions_for(args[:permissions])
    end
    json
  end
end