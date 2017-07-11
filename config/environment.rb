# Load the Rails application.
require File.expand_path('../application', __FILE__)
require 'go_secure'

# Initialize the Rails application.
Coughdrop::Application.initialize!

unless ENV['SKIP_VALIDATIONS']
  GoSecure.validate_encryption_key
  raise "DEFAULT_EMAIL_FROM must be defined as environment variable" unless ENV['DEFAULT_EMAIL_FROM']
  raise "SYSTEM_ERROR_EMAIL must be defined as environment variable" unless ENV['SYSTEM_ERROR_EMAIL']
end


AppSearcher.load_schemes