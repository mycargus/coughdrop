require 'spec_helper'

describe Pusher do
  it 'should push the message' do
    cred = OpenStruct.new
    sms = OpenStruct.new
    expect(Aws::Credentials).to receive(:new).and_return(cred)
    expect(Aws::SNS::Client).to receive(:new).and_return(sms)
    expect(sms).to receive(:publish).with({
      phone_number: '+1123456',
      message: "CoughDrop: hello friend",
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
    }).and_return(OpenStruct.new(message_id: 'asdf'))
    expect(Pusher.sms('123456', 'hello friend')).to eq('asdf')
  end
end
