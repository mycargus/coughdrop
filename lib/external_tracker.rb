module ExternalTracker
  def self.track_new_user(user)
    if user && user.external_email_allowed?
      Worker.schedule(ExternalTracker, :persist_new_user, user.global_id)
    end
  end
  
  def self.persist_new_user(user_id)
    user = User.find_by_path(user_id)
    return false unless user && user.external_email_allowed?
    return false unless ENV['HUBSPOT_KEY']
    return false unless user.settings && user.settings['email']

    d = user.devices[0]
    ip = d && d.settings['ip_address']
    location = nil
    if ip && ENV['IPSTACK_KEY']
      url = "http://api.ipstack.com/#{ip}?access_key=#{ENV['IPSTACK_KEY']}"
      begin
        res = Typhoeus.get(url)
        location = JSON.parse(res.body)
      rescue => e
      end
    end
    email = user.settings['email']
    city = nil
    state = nil
    if location && (location['country_code'] == 'USA' || location['country_code'] == 'US')
      city = location['city']
      state = location['region_name']
    end

    
    name = (user.settings['name'] || '').split(/\s/, 2)
    json = {
      properties: [
        {property: 'email', value: email },
        {property: 'firstname', value: name[0]},
        {property: 'lastname', value: name[1]},
        {property: 'city', value: city},
        {property: 'state', value: state}
      ]
    }
    # push to external system
    url = "https://api.hubapi.com/contacts/v1/contact/?hapikey=#{ENV['HUBSPOT_KEY']}"
    res = Typhoeus.post(url, {body: json.to_json, headers: {'Content-Type' => 'application/json'}})
    res.code
  end
end
