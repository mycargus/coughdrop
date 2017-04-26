require 'spec_helper'

describe Utterance, :type => :model do
  it "should generate defaults" do
    u = Utterance.new
    u.generate_defaults
    expect(u.data).not_to eq(nil)
    expect(u.data['image_url']).not_to eq(nil)
  end
  
  it "should track the default image url" do
    button_list = [
      {'label' => 'hat', 'image' => 'http://www.example.com/pib.png'},
      {'label' => 'cat', 'image' => 'http://www.example.com/pib.png'},
      {'label' => 'scat', 'image' => 'http://www.example.com/pic.png'}
    ]
    u = Utterance.create(:data => {
      'button_list' => button_list
    })
    expect(u.data['image_url']).to eq('http://www.example.com/pib.png')
    expect(u.data['default_image_url']).to eq(true)
  end
  
  it "should set the image url to the large image url if it's still set to the default image url" do
    button_list = [
      {'label' => 'hat', 'image' => 'http://www.example.com/pib.png'},
      {'label' => 'cat', 'image' => 'http://www.example.com/pib.png'},
      {'label' => 'scat', 'image' => 'http://www.example.com/pic.png'}
    ]
    user = User.create
    u = Utterance.create(:user => user, :data => {
      'button_list' => button_list
    })
    expect(u.data['image_url']).to eq('http://www.example.com/pib.png')
    expect(u.data['default_image_url']).to eq(true)
    expect(SentencePic).to receive(:generate).with(u).and_return('http://www.example.com/pix.png')
    u.generate_preview
    expect(u.data['image_url']).to eq('http://www.example.com/pix.png')
    expect(u.data['default_image_url']).to eq(true)
  end

  it "should no longer track the default image url once it's changed" do
    button_list = [
      {'label' => 'hat', 'image' => 'http://www.example.com/pib.png'},
      {'label' => 'cat', 'image' => 'http://www.example.com/pib.png'},
      {'label' => 'scat', 'image' => 'http://www.example.com/pic.png'}
    ]
    u = Utterance.create(:data => {
      'button_list' => button_list
    })
    expect(u.data['image_url']).to eq('http://www.example.com/pib.png')
    expect(u.data['default_image_url']).to eq(true)
    expect(SentencePic).to receive(:generate).with(u).and_return('http://www.example.com/pif.png')
    u.generate_preview
    expect(u.data['image_url']).to eq('http://www.example.com/pif.png')
    expect(u.data['default_image_url']).to eq(true)
  end
  
  it "should not se tthe image url to the large image url if it's not the default image url" do
    button_list = [
      {'label' => 'hat', 'image' => 'http://www.example.com/pib.png'},
      {'label' => 'cat', 'image' => 'http://www.example.com/pib.png'},
      {'label' => 'scat', 'image' => 'http://www.example.com/pic.png'}
    ]
    u = Utterance.create(:data => {
      'button_list' => button_list
    })
    expect(u.data['image_url']).to eq('http://www.example.com/pib.png')
    expect(u.data['default_image_url']).to eq(true)
    u.data['default_image_url'] = false
    expect(SentencePic).to receive(:generate).with(u).and_return('http://www.example.com/pif.png')
    u.generate_preview
    expect(u.data['image_url']).to eq('http://www.example.com/pib.png')
    expect(u.data['default_image_url']).to eq(false)
  end
  
  describe "share_with" do
    it "should allow sharing with a supervisor" do
      u1 = User.create
      u2 = User.create
      User.link_supervisor_to_user(u2, u1)
      button_list = [
        {'label' => 'hat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'cat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'scat', 'image' => 'http://www.example.com/pic.png'}
      ]
      u = Utterance.create(:data => {
        'button_list' => button_list
      })
      res = u.share_with({
        'supervisor_id' => u2.global_id
      }, u1)
      expect(res).to eq({:to => u2.global_id, :from => u1.global_id, :type => 'utterance'})
      expect(Worker.scheduled?(Utterance, :perform_action, {'id' => u.id, 'method' => 'deliver_to', 'arguments' => [{
        'user_id' => u2.global_id,
        'sharer_id' => u1.global_id
      }]})).to eq(true)
    end
    
    it "should allow sharing to an email address" do
      u1 = User.create
      button_list = [
        {'label' => 'hat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'cat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'scat', 'image' => 'http://www.example.com/pic.png'}
      ]
      u = Utterance.create(:data => {
        'button_list' => button_list
      })
      res = u.share_with({
        'email' => 'bob@example.com',
        'message' => 'hat cat scat'
      }, u1)
      expect(res).to eq({:from => u1.global_id, :to => 'bob@example.com', :type => 'email'})
      expect(Worker.scheduled?(Utterance, :perform_action, {'id' => u.id, 'method' => 'deliver_to', 'arguments' => [{
        'sharer_id' => u1.global_id,
        'email' => 'bob@example.com',
        'subject' => 'hat cat scat',
        'message' => 'hat cat scat'
      }]})).to eq(true)
    end
    
    it "should schedule a delivery for email shares" do
      u1 = User.create
      button_list = [
        {'label' => 'hat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'cat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'scat', 'image' => 'http://www.example.com/pic.png'}
      ]
      u = Utterance.create(:data => {
        'button_list' => button_list
      })
      res = u.share_with({
        'email' => 'bob@example.com',
        'message' => 'hat cat scat'
      }, u1)
      expect(res).to eq({:from => u1.global_id, :to => 'bob@example.com', :type => 'email'})
      expect(Worker.scheduled?(Utterance, :perform_action, {'id' => u.id, 'method' => 'deliver_to', 'arguments' => [{
        'sharer_id' => u1.global_id,
        'email' => 'bob@example.com',
        'subject' => 'hat cat scat',
        'message' => 'hat cat scat'
      }]})).to eq(true)
    end
    
    it "should return false if no valid share is specified" do
      u1 = User.create
      button_list = [
        {'label' => 'hat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'cat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'scat', 'image' => 'http://www.example.com/pic.png'}
      ]
      u = Utterance.create(:data => {
        'button_list' => button_list
      })
      res = u.share_with({}, nil)
      expect(res).to eq(false)
      res = u.share_with({}, u1)
      expect(res).to eq(false)
    end
    
    it "should return false if an invalid supervisor is specified" do
      u1 = User.create
      u2 = User.create
      button_list = [
        {'label' => 'hat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'cat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'scat', 'image' => 'http://www.example.com/pic.png'}
      ]
      u = Utterance.create(:data => {
        'button_list' => button_list
      })
      res = u.share_with({
        'supervisor_id' => u2.global_id
      }, u1)
      expect(res).to eq(false)
    end
  end
 
  describe "deliver_to" do
    it "should do nothing without a sharer" do
      u = Utterance.create
      expect{ u.deliver_to({}) }.to raise_error('sharer required')
      expect{ u.deliver_to({'email' => 'bob@example.com'}) }.to raise_error('sharer required')
    end
    
    it "should deliver to an email address" do
      u1 = User.create
      button_list = [
        {'label' => 'hat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'cat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'scat', 'image' => 'http://www.example.com/pic.png'}
      ]
      u = Utterance.create(:data => {
        'button_list' => button_list,
        'sentence' => 'hat cat scat'
      })
      expect(u.data['sentence']).to eq('hat cat scat')
      expect(UserMailer).to receive(:schedule_delivery).with(:utterance_share, {
        'subject' => 'hat cat scat',
        'message' => 'hat cat scat',
        'sharer_id' => u1.global_id,
        'to' => 'bob@example.com'
      })
      res = u.deliver_to({'sharer_id' => u1.global_id, 'email' => 'bob@example.com'})
      expect(res).to eq(true)
    end
    
    it "should deliver to a supervisor" do
      u1 = User.create
      u2 = User.create
      button_list = [
        {'label' => 'hat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'cat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'scat', 'image' => 'http://www.example.com/pic.png'}
      ]
      u = Utterance.create(:data => {
        'sentence' => 'hat cat scat'
      })
      expect(u).to receive(:notify).with('utterance_shared', {
        'sharer' => {'user_name' => u1.user_name, 'user_id' => u1.global_id},
        'user_id' => u2.global_id,
        'text' => 'hat cat scat'
      })
      res = u.deliver_to({'sharer_id' => u1.global_id, 'user_id' => u2.global_id})
      expect(res).to eq(true)
    end
  end
  
  describe "process_params" do
    it "should error without a user" do
      expect{ Utterance.process_new({}, {}) }.to raise_error("user required")
    end
    it "should process parameters" do
      user = User.create
      u = Utterance.process_new({:button_list => [{label: 'ok'}], :sentence => 'abc'}, {:user => user})
      expect(u.data['button_list']).to eq([{'label' => 'ok'}])
      expect(u.data['sentence']).to eq('abc')
      expect(u.user).to eq(user)
    end
  end
  
  describe "generate_preview" do
    it "should generate a preview" do
      button_list = [
        {'label' => 'hat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'cat', 'image' => 'http://www.example.com/pib.png'},
        {'label' => 'scat', 'image' => 'http://www.example.com/pic.png'}
      ]
      u = Utterance.create(:data => {
        'button_list' => button_list
      })
      expect(SentencePic).to receive(:generate).with(u).and_return("http://www.example.com/pid.png")
      Worker.process_queues
#      expect(u.reload.data['large_image_url']).to eq("http://www.example.com/pid.png")
    end
  end
end
