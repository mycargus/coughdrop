require 'spec_helper'

describe Uploadable, :type => :model do
  class FakeUploadable
    def self.before_save(*args); end
    def self.after_save(*args); end
    def self.after_destroy(*args); end
    include Uploadable
  end
  
  describe "file_type" do
    it "should return the correct file type" do
      expect(ButtonImage.new.file_type).to eq('images')
      expect(ButtonSound.new.file_type).to eq('sounds')
      expect(UserVideo.new.file_type).to eq('videos')
      expect(FakeUploadable.new.file_type).to eq('objects')
    end
  end
  
  describe "confirmation_key" do
    it "should generate a valid key" do
      i = ButtonImage.create
      i2 = ButtonImage.create
      k = i.confirmation_key
      expect(k).not_to eq(nil)
      expect(k.length).to be > 64
      expect(i.confirmation_key).to eq(k)
      expect(i2.confirmation_key).not_to eq(k)
    end
  end
  
  describe "full_filename" do
    it "should used the cached value if available" do
      i = ButtonImage.new(:settings => {'full_filename' => 'once/upon/a/time.png'})
      expect(i.full_filename).to eq('once/upon/a/time.png')
    end
    
    it "should add extensions only for known file types" do
      i = ButtonImage.create(:settings => {'content_type' => 'image/png'})
      expect(i.full_filename).to match(/\.png$/)
      i.settings['full_filename'] = nil
      i.settings['content_type'] = 'bacon/bacon'
      expect(i.full_filename).not_to match(/\./)
    end
    
    it "should add a hashed value for security" do
      i = ButtonImage.create(:settings => {'content_type' => 'image/png'})
      expect(i.full_filename.length).to be > 150
    end
    
    it "should store the value when returned" do
      i = ButtonImage.create(:settings => {'content_type' => 'image/png'})
      fn = i.full_filename
      i.reload
      expect(i.settings['full_filename']).to eq(fn)
    end
  end
  
  describe "content_type" do
    it "should return the value set in settings" do
      i = ButtonImage.new(:settings => {'content_type' => 'hippo/potamus'})
      expect(i.content_type).to eq('hippo/potamus')
    end
    
    it "should raise if no value found" do
      i = ButtonImage.new(:settings => {})
      expect { i.content_type }.to raise_error("content type required for uploads")
    end
  end

  describe "pending_upload?" do
    it "should return the correct boolean result" do
      i = ButtonImage.new(:settings => {})
      expect(i.pending_upload?).to eq(false)
      i.settings['pending'] = true
      expect(i.pending_upload?).to eq(true)
    end
  end

  describe "process_url" do
    it "should check if it's an already-stored URL, and not force re-upload if so" do
      i = ButtonImage.new(:settings => {})
      expect(Uploader).to receive(:valid_remote_url?).with("http://www.example.com/pic.png").and_return(true)
      i.process_url("http://www.example.com/pic.png", {})
      expect(i.url).to eq("http://www.example.com/pic.png")
    end
    
    it "should set to pending only if it's not already-stored and download is possible" do
      i = ButtonImage.new(:settings => {})
      expect(Uploader).to receive(:valid_remote_url?).with("http://www.example.com/pic.png").and_return(false)
      i.process_url("http://www.example.com/pic.png", {})
      expect(i.url).to eq(nil)
      expect(i.settings['pending_url']).to eq("http://www.example.com/pic.png")
      
      i = ButtonImage.new(:settings => {})
      expect(Uploader).to receive(:valid_remote_url?).with("http://www.example.com/pic.png").and_return(false)
      i.process_url("http://www.example.com/pic.png", {:download => false})
      expect(i.url).to eq("http://www.example.com/pic.png")
    end
    
    it "should set the instance variable @remote_upload_possible if specified during processing" do
      i = ButtonImage.new(:settings => {})
      expect(Uploader).to receive(:valid_remote_url?).with("http://www.example.com/pic.png").and_return(true)
      expect(i.instance_variable_get('@remote_upload_possible')).to eq(nil)
      i.process_url("http://www.example.com/pic.png", {:remote_upload_possible => true})
      expect(i.instance_variable_get('@remote_upload_possible')).to eq(true)
    end
  end

  describe "check_for_pending" do
    it "should set to pending if not already saved and a valid pending_url set" do
      i = ButtonImage.new(:settings => {})
      i.check_for_pending
      expect(i.settings['pending']).to eq(true)
      
      i.url = "http://www.pic.com"
      i.check_for_pending
      expect(i.settings['pending']).not_to eq(true)
      
      i.instance_variable_set('@remote_upload_possible', true)
      i.settings['pending_url'] = "http://www.pic.com"
      i.check_for_pending
      expect(i.settings['pending']).to eq(true)
    end
    
    it "should unset from pending and schedule a background download if client can't upload" do
      i = ButtonImage.new(:settings => {})
      i.settings['pending_url'] = "http://www.example.com"
      i.instance_variable_set('@remote_upload_possible', false)
      i.check_for_pending
      expect(i.settings['pending']).to eq(false)
      expect(i.url).to eq("http://www.example.com")
      expect(i.instance_variable_get('@schedule_upload_to_remote')).to eq(true)
    end
  end

  describe "upload_after_save" do
    it "should schedule an upload only if set" do
      s = ButtonSound.create(:settings => {})
      s.settings['pending_url'] = 'http://www.example.com/pic.png'
      s.instance_variable_set('@schedule_upload_to_remote', false)
      s.upload_after_save
      expect(Worker.scheduled?(ButtonSound, 'perform_action', {'id' => s.id, 'method' => 'upload_to_remote', 'arguments' => ['http://www.example.com/pic.png']})).to eq(false)

      s.instance_variable_set('@schedule_upload_to_remote', true)
      s.upload_after_save
      expect(Worker.scheduled?(ButtonSound, 'perform_action', {'id' => s.id, 'method' => 'upload_to_remote', 'arguments' => ['http://www.example.com/pic.png']})).to eq(true)
    end
  end

  describe "remote_upload_params" do
    it "should collect upload parameters, including a success callback" do
      s = ButtonSound.create(:settings => {'content_type' => 'image/png'})
      res = s.remote_upload_params
      expect(res[:upload_url]).not_to eq(nil)
      expect(res[:upload_params]).not_to eq(nil)
      expect(res[:success_url]).to eq("#{JsonApi::Json.current_host}/api/v1/#{s.file_type}/#{s.global_id}/upload_success?confirmation=#{s.confirmation_key}")
    end
  end

  describe "upload_to_remote" do
    it "should fail unless the record is saved" do
      s = ButtonSound.new
      expect { s.upload_to_remote("") }.to raise_error("must have id first")
    end
    
    it "should handle data-uris" do
      uri = "data:image/webp;base64,UklGRjIAAABXRUJQVlA4ICYAAACyAgCdASoCAAEALmk0mk0iIiIiIgBoSygABc6zbAAA/v56QAAAAA=="
      s = ButtonSound.create(:settings => {})
      res = OpenStruct.new(:success? => true)
      expect(Typhoeus).to receive(:post) { |url, args|
        f = args[:body][:file]
        expect(f.size).to eq(58)
      }.and_return(res)
      s.upload_to_remote(uri)
      expect(s.url).not_to eq(nil)
      expect(s.settings['pending']).to eq(false)
      expect(s.settings['content_type']).to eq('image/webp')
    end
    
    it "should handle downloads" do
      s = ButtonSound.create(:settings => {})
      res = OpenStruct.new(:success? => true, :headers => {'Content-Type' => 'audio/mp3'}, :body => "abcdefg")
      expect(Typhoeus).to receive(:get).and_return(res)
      res = OpenStruct.new(:success? => true)
      expect(Typhoeus).to receive(:post) { |url, args|
        f = args[:body][:file]
        expect(f.size).to eq(7)
      }.and_return(res)
      s.upload_to_remote("http://pic.com/cow.png")
      expect(s.url).not_to eq(nil)
      expect(s.settings['pending']).to eq(false)
      expect(s.settings['content_type']).to eq('audio/mp3')
    end
    
    it "should error gracefully on mismatched content type header" do
      s = ButtonSound.create(:settings => {})
      res = OpenStruct.new(:success? => true, :headers => {'Content-Type' => 'image/png'}, :body => "abcdefg")
      expect(Typhoeus).to receive(:get).and_return(res)
      s.upload_to_remote("http://pic.com/cow.png")
      expect(s.url).to eq(nil)
      expect(s.settings['source_url']).to eq("http://pic.com/cow.png")
      expect(s.settings['errored_pending_url']).to eq("http://pic.com/cow.png")
      expect(s.settings['pending']).to eq(true)
    end
    
    it "should error gracefully on bad http response" do
      s = ButtonSound.create(:settings => {})
      res = OpenStruct.new(:success? => false, :headers => {'Content-Type' => 'audio/mp3'}, :body => "abcdefg")
      expect(Typhoeus).to receive(:get).and_return(res)
      s.upload_to_remote("http://pic.com/cow.png")
      expect(s.url).to eq(nil)
      expect(s.settings['source_url']).to eq("http://pic.com/cow.png")
      expect(s.settings['errored_pending_url']).to eq("http://pic.com/cow.png")
      expect(s.settings['pending']).to eq(true)
    end
    
    it "should upload to the remote location" do
      s = ButtonSound.create(:settings => {})
      res = OpenStruct.new(:success? => true, :headers => {'Content-Type' => 'audio/mp3'}, :body => "abcdefg")
      expect(Typhoeus).to receive(:get).and_return(res)
      res = OpenStruct.new(:success? => true)
      expect(Typhoeus).to receive(:post) { |url, args|
        expect(url).to eq(Uploader.remote_upload_config[:upload_url])
      }.and_return(res)
      s.upload_to_remote("http://pic.com/cow.png")
      expect(s.url).not_to eq(nil)
      expect(s.settings['pending']).to eq(false)
      expect(s.settings['content_type']).to eq('audio/mp3')
    end
    
    it "should measure image height if not already set" do
      s = ButtonImage.create(:settings => {})
      res = OpenStruct.new(:success? => true, :headers => {'Content-Type' => 'image/png'}, :body => "abcdefg")
      expect(Typhoeus).to receive(:get).and_return(res)
      res = OpenStruct.new(:success? => true)
      expect(Typhoeus).to receive(:post) { |url, args|
        f = args[:body][:file]
        expect(f.size).to eq(7)
      }.and_return(res)
      
      expect(s).to receive(:'`').and_return("A\nB\nGeometry:  100x150")
      s.upload_to_remote("http://pic.com/cow.png")
      expect(s.url).not_to eq(nil)
      expect(s.settings['pending']).to eq(false)
      expect(s.settings['content_type']).to eq('image/png')
      expect(s.settings['width']).to eq(100)
      expect(s.settings['height']).to eq(150)
    end
  end
  
  describe "url_for" do
    it 'should return the correct value' do
      u = User.create
      i = ButtonImage.new(url: 'http://www.example.com/api/v1/users/1234/protected_images/bacon')
      expect(i.url_for(nil)).to eq('http://www.example.com/api/v1/users/1234/protected_images/bacon')
      expect(i.url_for(u)).to eq("http://www.example.com/api/v1/users/1234/protected_images/bacon?user_token=#{u.user_token}")
      i.url = "http://www.example.com/api/v1/users/1234/protected_images/bacon?a=1"
      expect(i.url_for(u)).to eq("http://www.example.com/api/v1/users/1234/protected_images/bacon?a=1&user_token=#{u.user_token}")
    end
  end
end
