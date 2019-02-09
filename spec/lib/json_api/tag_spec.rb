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


# module JsonApi::Tag
#   extend JsonApi::Json
  
#   TYPE_KEY = 'tag'
#   DEFAULT_PAGE = 10
#   MAX_PAGE = 25
    
#   def self.build_json(tag, args={})
#     json = {}
    
#     json['id'] = tag.global_id
#     json['tag_id'] = tag.tag_id
#     json['public'] = tag.public
#     if tag.data['button']
#       json['button'] = tag.data['button']
#     else
#       json['label'] = tag.data['label']
#     end
#     json
#   end
# end
