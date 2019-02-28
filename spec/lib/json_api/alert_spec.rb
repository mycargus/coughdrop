require 'spec_helper'

describe JsonApi::Alert do
  it 'should generate a valid alert' do
    u = User.create
    d = Device.create(user: u)
    utterance = Utterance.create(user: u, data: {'sentence' => 'how are you'})
    note = LogSession.create(user: u, author: u, device: d, log_type: 'note', data: {'note' => {'text' => 'ok cool'}})
    contact_note = LogSession.create(user: u, author: u, device: d, log_type: 'note', data: {'author_contact' => {'name' => 'Prius', 'bacon' => true}, 'note' => {'text' => 'ok whatevs'}})
    json = JsonApi::Alert.build_json(utterance)
    expect(json['id']).to eq(Webhook.get_record_code(utterance))
    expect(json['text']).to eq('how are you')
    expect(json['author']['name']).to eq(u.user_name)

    json = JsonApi::Alert.build_json(note)
    expect(json['id']).to eq(Webhook.get_record_code(note))
    expect(json['text']).to eq('ok cool')
    expect(json['author']['name']).to eq(u.user_name)

    json = JsonApi::Alert.build_json(contact_note)
    expect(json['id']).to eq(Webhook.get_record_code(contact_note))
    expect(json['text']).to eq('ok whatevs')
    expect(json['author']['name']).to eq('Prius')
    expect(json['author']['bacon']).to eq(nil)
  end
end
