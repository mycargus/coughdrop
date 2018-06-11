module JsonApi::Token
  def self.as_json(user, device, args={})
    json = {}
    
    json['access_token'] = device.token
    json['token_type'] = 'bearer'
    json['user_name'] = user.user_name
    json['user_id'] = user.global_id
    # the anonymized user id should be consistent for the external tool
    dev_key = device.developer_key_id == 0 ? device.id : device.developer_key_id
    json['anonymized_user_id'] = user.anonymized_identifier("external_for_#{dev_key}")
    json['scopes'] = device.permission_scopes
    
    json
  end
end
