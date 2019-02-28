require 'spec_helper'

describe JsonApi::Tag do
  it 'should generate a valid tag' do
    u = User.create
    t = NfcTag.process_new({'label' => 'bacon', 'tag_id' => 'asdfasdf'}, {'user' => u})
    json = JsonApi::Tag.build_json(t)
    expect(json['id']).to eq(t.global_id)
    expect(json['tag_id']).to eq('asdfasdf')
    expect(json['label']).to eq('bacon')
    expect(json['button']).to eq(nil)
    expect(json['public']).to eq(false)
  end
end
