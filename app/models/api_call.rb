class ApiCall < ActiveRecord::Base
  include SecureSerialize
  secure_serialize :data
  replicated_model
  
  def self.log(token, user, request, response, time)
    return true if ENV['DISABLE_API_CALL_LOGGING']
    # TODO: is there a better way to log this? It's too huge to actually use
    if request && request.path && request.path.match(/^\/api\/v\d+/) && token && user && response
      call = ApiCall.new
      call.user_id = user.id
      call.data ||= {}
      call.data['url'] = request.url
      call.data['method'] = request.method
      call.data['access_token'] = token
      call.data['status'] = response.code
      call.data['time'] = time
      call.save
    else
      false
    end
  end
  
  def self.flush
    ApiCall.where(['created_at < ?', 2.months.ago]).delete_all
  end
end
