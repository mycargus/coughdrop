class ContactMessage < ActiveRecord::Base
  include GlobalId
  include Processable
  include SecureSerialize
  include Async
  secure_serialize :settings
  replicated_model  
  
  after_create :deliver_message
  
  def deliver_message
    if @deliver_remotely
      @deliver_remotely = false
      self.schedule(:deliver_remotely)
    else
      AdminMailer.schedule_delivery(:message_sent, self.global_id)
    end
    true
  end
  
  def process_params(params, non_user_params)
    self.settings ||= {}
    ['name', 'email', 'subject', 'message', 'recipient'].each do |key|
      self.settings[key] = process_string(params[key]) if params[key]
    end
    ['ip_address', 'user_agent', 'version'].each do |key|
      self.settings[key] = non_user_params[key] if non_user_params[key]
    end
    if non_user_params['api_user']
      self.settings['name'] = non_user_params['api_user'].settings['name']
      self.settings['email'] = non_user_params['api_user'].settings['email']
      self.settings['user_id'] = non_user_params['api_user'].global_id
    end
    if params['recipient'] && params['recipient'].match(/support/) && ENV['ZENDESK_DOMAIN']
      if !self.settings['email']
        add_processing_error("Email required for support tickets")
        return false
      end
      @deliver_remotely = true
    end
    true
  end
  
  def deliver_remotely
    body = (self.settings['message'] || 'no message') + "<br/><br/><span style='font-style: italic;'>"
    user = User.find_by_path(self.settings['user_id']) if self.settings['user_id']
    if user
      body += (user.user_name) + '<br/>'
    end
    body += (self.settings['ip_address'] ? "ip address: #{self.settings['ip_address']}" : 'no IP address found') + '<br/>'
    body += (self.settings['version'] ? "app version: #{self.settings['version']}" : 'no app version found') + '<br/>'
    body += (self.settings['user_agent'] ? "browser: #{self.settings['user_agent']}" : 'no user agent found') + "</span>"
    basic_auth = "#{ENV['ZENDESK_USER']}/token:#{ENV['ZENDESK_TOKEN']}"
    endpoint = "https://#{ENV['ZENDESK_DOMAIN']}/api/v2/tickets.json"
    json = {
      'ticket' => {
        'requester' => {
          'name' => self.settings['name'] || self.settings['email'],
          'email' => self.settings['email']
        },
        'subject' => (self.settings['subject'].blank? ? "Ticket #{Date.today.iso8601}" : self.settings['subject']),
        'comment' => {
          'html_body' => body
        }
      }
    }
    res = Typhoeus.post(endpoint, {body: json.to_json, userpwd: basic_auth, headers: {'Content-Type' => 'application/json'}})
    if res.code == 201
      true
    else
      self.settings['error'] = res.body
      self.save
      AdminMailer.schedule_delivery(:message_sent, self.global_id)
      false
    end
  end
end
