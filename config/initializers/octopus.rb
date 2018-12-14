unless ENV['SKIP_VALIDATIONS']
  if defined?(Octopus) && Octopus.enabled?
    count = case (Octopus.config[Rails.env].values[0].values[0] rescue nil)
    when Hash
      Octopus.config[Rails.env].map{|group, configs| configs.count}.sum rescue 0
    else
      Octopus.config[Rails.env].keys.count rescue 0
    end

    puts "=> #{count} #{'database'.pluralize(count)} enabled as read-only #{'slave'.pluralize(count)}"
  end
end