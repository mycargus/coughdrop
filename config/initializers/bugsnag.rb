require 'bugsnag'

Bugsnag.configure do |config|
  config.meta_data_filters += ['User-Agent', 'X-Device-Id', 'X-Forwarded-For', 'clientIp', 'client_ip', 'params', 'request.clientIp', 'request.params']
end