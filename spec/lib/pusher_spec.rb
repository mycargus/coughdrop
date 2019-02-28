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
    expect(Pusher.sms('123456', 'hello friend')).to eq(['asdf'])
  end

  it 'should support E.164 formatting' do
    cred = OpenStruct.new
    sms = OpenStruct.new
    expect(Aws::Credentials).to receive(:new).and_return(cred)
    expect(Aws::SNS::Client).to receive(:new).and_return(sms)
    expect(sms).to receive(:publish).with({
      phone_number: '+15558675309',
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
    expect(Pusher.sms('(555) 867-5309', 'hello friend')).to eq(['asdf'])
  end

  it 'should deliver to multiple addresses if combined' do
    cred = OpenStruct.new
    sms = OpenStruct.new
    expect(Aws::Credentials).to receive(:new).and_return(cred).at_least(1).times
    expect(Aws::SNS::Client).to receive(:new).and_return(sms).at_least(1).times
    expect(sms).to receive(:publish).with({
      phone_number: '+15558675309',
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
    expect(sms).to receive(:publish).with({
      phone_number: '+15551234567',
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
    }).and_return(OpenStruct.new(message_id: 'jkl'))
    expect(Pusher.sms('(555) 867-5309, (555) 123-4567', 'hello friend')).to eq(['asdf', 'jkl'])
  end
end
