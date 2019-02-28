require 'aws-sdk'

module Pusher
  def self.sms(phone, message)
    client = config
    raise "phone missing" unless phone
    raise "message missing" unless message
    phone.strip!
    if phone.match(/,/)
      return  phone.split(/,/).map{|p| Pusher.sms(p, message)[0]}
    end
    phones = phone.split(/,/)
    if !phone.match(/^\+\d/)
      phone = "+1" + phone
    end
    phone = phone.gsub(/[^\+\d]/, '')
    res = client.publish({
      phone_number: phone,
      message: "CoughDrop: #{message}",
      message_attributes: {
        "AWS.SNS.SMS.MaxPrice" => {
          data_type: "Number",
          string_value: "0.5"
        },
        "AWS.SNS.SMS.SenderID" => {
          data_type: "String",
          string_value: "CoughDrop"
        }
      }
    })
    message_id = res.message_id
    [message_id]
  end

  def self.config
    cred = Aws::Credentials.new((ENV['TRANSCODER_KEY'] || ENV['AWS_KEY']), (ENV['TRANSCODER_SECRET'] || ENV['AWS_SECRET']))
    Aws::SNS::Client.new(region: (ENV['TRANSCODER_REGION'] || ENV['AWS_REGION']), credentials: cred)
  end
end