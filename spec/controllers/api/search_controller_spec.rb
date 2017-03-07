require 'spec_helper'

describe Api::SearchController, :type => :controller do
  describe "symbols" do
    it "should require api token" do
      get :symbols, params: {:q => 'hat'}
      assert_missing_token
    end
    
    it "should make an opensymbols api call and return the adjusted results" do
      token_user
      list = [
        {'extension' => 'png', 'name' => 'bob'},
        {'extension' => 'gif', 'name' => 'fred'}
      ]
      res = OpenStruct.new(:body => list.to_json)
      expect(Typhoeus).to receive(:get).with("https://www.opensymbols.org/api/v1/symbols/search?q=hat", :ssl_verifypeer => false).and_return(res)
      get :symbols, params: {:q => 'hat'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq([
        {'extension' => 'png', 'content_type' => 'image/png', 'name' => 'bob'},
        {'extension' => 'gif', 'content_type' => 'image/gif', 'name' => 'fred'}
      ])
    end
    
    it "should tally any search queries that have no results" do
      RedisInit.default.del('missing_symbols')
      token_user
      list = []
      list2 = [
        {'extension' => 'png', 'name' => 'bob'},
        {'extension' => 'gif', 'name' => 'fred'}
      ]
      res = OpenStruct.new(:body => list.to_json)
      res2 = OpenStruct.new(:body => list2.to_json)
      expect(Typhoeus).to receive(:get).with("https://www.opensymbols.org/api/v1/symbols/search?q=hat", :ssl_verifypeer => false).and_return(res)
      expect(Typhoeus).to receive(:get).with("https://www.opensymbols.org/api/v1/symbols/search?q=hats", :ssl_verifypeer => false).and_return(res2)
      get :symbols, params: {:q => 'hat'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq([])
      get :symbols, params: {:q => 'hats'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json.length).to eq(2)
      
      hash = RedisInit.default.hgetall('missing_symbols')
      expect(hash).not_to eq(nil)
      expect(hash['hat']).to eq('1')
      expect(hash['hats']).to eq(nil)
    end
  end
  
  describe "protected_symbols" do
    it "should require api token" do
      get :protected_symbols, params: {:q => 'hats'}
      assert_missing_token
    end
    
    it "should require access to the integration" do
      token_user
      get :protected_symbols, params: {:q => 'hats'}
      assert_unauthorized
    end
    
    it "should return a result if authorized" do
      token_user
      expect(Uploader).to receive(:find_images).with('gerbils', 'lessonpix', @user).and_return([])
      get :protected_symbols, params: {:q => 'gerbils', :library => 'lessonpix'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq([])
    end
    
    it "should check for the existence of a user if specified" do
      token_user
      get :protected_symbols, params: {:q => 'feather', :user_name => 'nobody'}
      assert_not_found('nobody')
    end
    
    it "should check for edit permission for the user if specified" do
      token_user
      u = User.create
      User.link_supervisor_to_user(@user, u, nil, false)
      get :protected_symbols, params: {:q => 'walrus', :user_name => u.user_name}
      assert_unauthorized
    end
    
    it "should allow searching on behalf of an authorized user" do
      token_user
      u = User.create
      expect(Uploader).to receive(:lessonpix_credentials).with(u).and_return({'pid' =>  '1', 'username' => 'bob', 'token' => 'asdf'})
      expect(Typhoeus).to receive(:get).with("http://lessonpix.com/apiKWSearch.php?pid=1&username=bob&token=asdf&word=snowman&fmt=json&allstyles=n&limit=30").and_return(OpenStruct.new({body: [
      ].to_json}))
      User.link_supervisor_to_user(@user, u, nil, true)
      get :protected_symbols, params: {:q => 'snowman', :library => 'lessonpix', :user_name => u.user_name}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq([])
    end

    it 'should search for symbols' do
      token_user
      expect(Uploader).to receive(:find_images).with('cheese', 'some_library', @user).and_return([
        {
          'url' => 'http://www.example.com/pic1.png',
          'content_type' => 'image/png',
          'name' => 'my pic',
          'width' => 200,
          'height' => 200,
          'license' => {
            'type' => 'public_domain',
            'author_name' => 'bob',
            'author_url' => 'http://www.example.com/bob',
            'source_url' => 'http://www.example.com/bob/pic1'
          }
        },
        {
          'url' => 'http://www.example.com/pic2.jpg',
          'content_type' => 'image/jpeg',
          'name' => 'my pic',
          'width' => 300,
          'height' => 300,
          'license' => {
            'type' => 'private',
            'author_name' => 'fred',
            'author_url' => 'http://www.example.com/fred',
            'source_url' => 'http://www.example.com/fred/pic2',
            'copyright_notice_url' => 'http://www.example.com/c'
          }
        }
      ])
      get 'protected_symbols', params: {'q' => 'cheese', 'library' => 'some_library'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq([
        {
         'image_url' => 'http://www.example.com/pic1.png',
         'content_type' => 'image/png',
         'name' => 'my pic',
         'width' => 200,
         'height' => 200,
         'external_id' => nil,
         'finding_user_name' => @user.user_name,
         'protected' => true,
         'public' => false,
         'license' => 'public_domain',
         'author' => 'bob',
         'author_url' => 'http://www.example.com/bob',
         'source_url' => 'http://www.example.com/bob/pic1',
         'copyright_notice_url' => nil
        },
        {
         'image_url' => 'http://www.example.com/pic2.jpg',
         'content_type' => 'image/jpeg',
         'name' => 'my pic',
         'width' => 300,
         'height' => 300,
         'external_id' => nil,
         'finding_user_name' => @user.user_name,
         'protected' => true,
         'public' => false,
         'license' => 'private',
         'author' => 'fred',
         'author_url' => 'http://www.example.com/fred',
         'source_url' => 'http://www.example.com/fred/pic2',
         'copyright_notice_url' => 'http://www.example.com/c'
        }
      ])
    end
  end
  
  describe "proxy" do
    it "should require api token" do
      get :proxy, params: {:url => 'http://www.example.com/pic.png'}
      assert_missing_token
    end
    
    it "should return content type and data-uri" do
      token_user
      expect(controller).to receive(:get_url_in_chunks).and_return(['image/png', '12345'])
      get :proxy, params: {:url => 'http://www.example.com/pic.png'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['content_type']).to eq('image/png')
      expect(json['data']).to eq('data:image/png;base64,MTIzNDU=')
    end
    
    it "should return error response if there are unexpected problems" do
      token_user
      expect(controller).to receive(:get_url_in_chunks).and_raise(Api::SearchController::BadFileError, 'something bad')
      get :proxy, params: {:url => 'http://www.example.com/pic.png'}
      expect(response).not_to be_success
      json = JSON.parse(response.body)
      expect(json['error']).to eq('something bad')
    end
    
    it "should escape the URI if needed" do
      token_user
      expect(controller).to receive(:get_url_in_chunks) { |req|
        expect(req.url).to eq("http://www.example.com/a%20good%20pic.png")
        true
      }.and_return(['image/png', '12345'])
      get :proxy, params: {:url => 'http://www.example.com/a good pic.png'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['content_type']).to eq('image/png')
      expect(json['data']).to eq('data:image/png;base64,MTIzNDU=')
    end

    it "should not re-escape the URI if not needed" do
      token_user
      expect(controller).to receive(:get_url_in_chunks) { |req|
        expect(req.url).to eq("http://www.example.com/a%20good%20pic.png")
        true
      }.and_return(['image/png', '12345'])
      get :proxy, params: {:url => 'http://www.example.com/a%20good%20pic.png'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json['content_type']).to eq('image/png')
      expect(json['data']).to eq('data:image/png;base64,MTIzNDU=')
    end
  end
  
  describe "apps" do
    it "should require an api token" do
      get :apps, params: {:q => 'hat', :os => 'ios'}
      assert_missing_token
    end
    
    it "should return the results of a call to AppSearcher" do
      token_user
      expect(AppSearcher).to receive(:find).with('hat', 'ios').and_return({})
      get :apps, params: {:q => 'hat', :os => 'ios'}
      expect(response).to be_success
      expect(response.body).to eq("{}")
      
      expect(AppSearcher).to receive(:find).with('hat', 'android').and_return([])
      get :apps, params: {:q => 'hat', :os => 'android'}
      expect(response).to be_success
      expect(response.body).to eq("[]")
    end
  end
  
  describe "get_url_in_chunks" do
    class FakeRequest
      def initialize(header_ok=true, content_type="text/text", body_size=100)
        @header_ok = header_ok
        @content_type = content_type
        @body_size = body_size
      end
      def on_headers(&block)
        @header_block = block
      end
      
      def on_body(&block)
        @body_block = block
      end
      
      def on_complete(&block)
        @complete_block = block
      end
      
      def run
        res = OpenStruct.new(:success? => @header_ok, :code => (@header_ok ? 200 : 400), :headers => {'Content-Type' => @content_type})
        if @body_size > 0
          @header_block.call(res)
          so_far = 0
          while so_far < @body_size
            so_far += 100
            str = "0123456789" * 10
            @body_block.call(str)
          end
        end
        @complete_block.call(res)
      end
    end
    it "should raise on invalid file types" do
      req = FakeRequest.new
      expect { controller.get_url_in_chunks(req) }.to raise_error(Api::SearchController::BadFileError, 'Invalid file type, text/text')
    end
    
    it "should raise on non-200 response" do
      req = FakeRequest.new(false)
      expect { controller.get_url_in_chunks(req) }.to raise_error(Api::SearchController::BadFileError, 'File not retrieved, status 400')
    end
    
    it "should raise on too-large a file" do
      stub_const("Uploader::CONTENT_LENGTH_RANGE", 200)
      req = FakeRequest.new(true, "image/png", Uploader::CONTENT_LENGTH_RANGE + 1)
      expect { controller.get_url_in_chunks(req) }.to raise_error(Api::SearchController::BadFileError, 'File too big (> 200)')
    end
    
    it "should raise on a fail that only calls complete" do
      req = FakeRequest.new(false, "text/text", 0)
      expect { controller.get_url_in_chunks(req) }.to raise_error(Api::SearchController::BadFileError, 'Bad file, 400')
    end
    
    it "should return content_type and binary data on success" do
      req = FakeRequest.new(true, "image/png", 100)
      expect(controller.get_url_in_chunks(req)).to eq(['image/png', '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789'])
    end
  end
  
  describe "parts_of_speech" do
    it "should require api token" do
      get :parts_of_speech, params: {:q => 'hat'}
      assert_missing_token
    end
    
    it "should look up a word" do
      token_user
      expect(WordData).to receive(:find_word).with('hat').and_return({
        :word => 'hat',
        :types => ['noun']
      })
      get :parts_of_speech, params: {:q => 'hat'}
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to eq({
        'word' => 'hat',
        'types' => ['noun']
      })
    end
  end
end
