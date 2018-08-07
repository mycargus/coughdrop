module JsonApi::Gift
  extend JsonApi::Json
  
  TYPE_KEY = 'gift'
  DEFAULT_PAGE = 25
  MAX_PAGE = 50
    
  def self.build_json(gift, args={})
    json = {}
    json['id'] = "#{gift.code}y#{gift.code_verifier}"
    json['gift_type'] = gift.gift_type
    json['created'] = gift.created_at.iso8601
    json['code'] = gift.code
    json['duration'] = gift.duration
    json['seconds'] = gift.settings['seconds_to_add'].to_i
    json['licenses'] = gift.settings['licenses']
    json['total_codes'] = gift.settings['total_codes']
    json['redeemed_codes'] = (gift.settings['codes'] || {}).to_a.map(&:last).select{|v| v != nil }.length
    json['activated_discounts'] = (gift.settings['activations'] || []).length
    json['discount'] = gift.discount_percent
    json['limit'] = gift.settings['limit']
    json['expires'] = gift.settings['expires']
    json['include_extras'] = gift.settings['include_extras']
    json['org_connected'] = gift.gift_type == 'multi_codes' && !!gift.settings['org_id']
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

    if gift.settings['activations'] && json['permissions'] && json['permissions']['manage']
      user_ids = gift.settings['activations'].map{|k, c| c && c['receiver_id'] }
      users = {}
      User.find_all_by_global_id(user_ids.uniq).each do |user|
      end
    end
    ['activations', 'codes'].each do |list|
      if gift.settings[list] && json['permissions'] && json['permissions']['manage']
        user_ids = gift.settings[list].map{|k, c| (c && c['receiver_id']) || (k && k['receiver_id'])}
        users = {}
        User.find_all_by_global_id(user_ids.uniq).each do |user|
          users[user.global_id] = user
        end
        json[list] = gift.settings[list].map do |key, code|
          if list == 'codes'
            user_json = code && users[code['receiver_id']] && JsonApi::User.build_json(users[code['receiver_id']], :limited_identity => true)
            {
              code: key,
              redeemed: !!code,
              redeemed_at: code && code['redeemed_at'],
              receiver: user_json ? user_json : nil
            }
          else
            user_json = users[key['receiver_id']] && JsonApi::User.build_json(users[key['receiver_id']], :limited_identity => true)
            {
              activated_at: key['activated_at'],
              receiver: user_json ? user_json : nil
            }
          end
        end
      end
    end

    json
  end
end