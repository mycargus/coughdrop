require 'spec_helper'

describe Api::TagsController, :type => :controller do
  describe 'index' do
    it 'should require an api token' do
      get :index, params: {}
      assert_missing_token
    end

    it 'should return results for the current user' do
      u2 = User.create
      token_user
      NfcTag.process_new({'label' => 'what'}, {'user' => @user})
      NfcTag.process_new({'label' => 'ever'}, {'user' => u2})
      get :index
      json = assert_success_json
      expect(json['tag'].length).to eq(1)
      expect(json['tag'][0]['label']).to eq('what')
    end

    it 'should return results for the specified user' do
      u2 = User.create
      token_user
      User.link_supervisor_to_user(@user, u2, nil, true)
      NfcTag.process_new({'label' => 'what'}, {'user' => @user})
      NfcTag.process_new({'label' => 'ever'}, {'user' => u2})
      get :index, params: {'user_id' => u2.global_id}
      json = assert_success_json
      expect(json['tag'].length).to eq(1)
      expect(json['tag'][0]['label']).to eq('ever')
    end

    it 'should not allow looking up a non-existent user' do
      token_user
      get :index, params: {'user_id' => 'asdf'}
      assert_not_found('asdf')
    end
    
    it 'should not allow looking up an unauthorized user' do
      u2 = User.create
      token_user
      get :index, params: {'user_id' => u2.global_id}
      assert_unauthorized
    end

    it 'should return paginated results' do
      token_user
      50.times do |i|
        NfcTag.process_new({'label' => 'what'}, {'user' => @user})
      end

      get :index
      json = assert_success_json
      expect(json['tag'].length).to eq(10)
      expect(json['tag'][0]['label']).to eq('what')
    end
  end

  describe 'create' do
    it 'should require an api token' do
      post :create, params: {}
      assert_missing_token
    end

    it 'should create the tag' do
      token_user
      post :create, params: {tag: {'label' => 'bacon'}}
      expect(response).to be_success
      json = JSON.parse(response.body)
      tag = NfcTag.find_by_global_id(json['tag']['id'])
      expect(tag).to_not eq(nil)
      expect(json['tag']['label']).to eq('bacon')
    end
  end

  describe 'show' do
    it 'should require an api token' do
      get :show, params: {id: 'asdf'}
      assert_missing_token
    end

    it 'should require a valid tag' do
      token_user
      get :show, params: {id: 'asdf'}
      assert_not_found('asdf')
    end

    it 'should require authorization if not public' do
      u = User.create
      t = NfcTag.process_new({'label' => 'asdf'}, {'user' => u})
      token_user
      get :show, params: {id: t.global_id}
      assert_unauthorized
    end

    it 'should return a public result' do
      u = User.create
      t = NfcTag.process_new({'label' => 'asdf', 'public' => true}, {'user' => u})
      token_user
      get :show, params: {id: t.global_id}
      json = assert_success_json
      expect(json['tag']['id']).to eq(t.global_id)
    end

    it 'should return a private result if authorized' do
      token_user
      t = NfcTag.process_new({'label' => 'asdf'}, {'user' => @user})
      get :show, params: {id: t.global_id}
      json = assert_success_json
      expect(json['tag']['id']).to eq(t.global_id)
    end

    it 'should find a tag by global_id' do
      token_user
      t = NfcTag.process_new({'label' => 'asdf'}, {'user' => @user})
      get :show, params: {id: t.global_id}
      json = assert_success_json
      expect(json['tag']['id']).to eq(t.global_id)
    end

    it 'should fall back to the tag_id' do
      token_user
      t = NfcTag.process_new({'label' => 'asdf', 'tag_id' => 'asdfasdf'}, {'user' => @user})
      get :show, params: {id: 'asdfasdf'}
      json = assert_success_json
      expect(json['tag']['id']).to eq(t.global_id)
    end

    it 'should prefer the user-connected record for a tag_id' do
      token_user
      t = NfcTag.process_new({'label' => 'asdf', 'tag_id' => 'asdfasdf'}, {'user' => @user})
      u = User.create
      t2 = NfcTag.process_new({'label' => 'qwer', 'tag_id' => 'asdfasdf'}, {'user' => u})
      get :show, params: {id: 'asdfasdf'}
      json = assert_success_json
      expect(json['tag']['id']).to eq(t.global_id)
    end

    it 'should prefer the user-connected most-recent record if there is more than one' do
      token_user
      t = NfcTag.process_new({'label' => 'asdf', 'tag_id' => 'asdfasdf'}, {'user' => @user})
      t2 = NfcTag.process_new({'label' => 'qwer', 'tag_id' => 'asdfasdf'}, {'user' => @user})
      get :show, params: {id: 'asdfasdf'}
      json = assert_success_json
      expect(json['tag']['id']).to eq(t2.global_id)
    end

    it 'should fall back to the most-recent public record for a tag_id' do
      u = User.create
      token_user
      t = NfcTag.process_new({'label' => 'asdf', 'tag_id' => 'asdfasdf', 'public' => true}, {'user' => u})
      t2 = NfcTag.process_new({'label' => 'qwer', 'tag_id' => 'asdfasdf', 'public' => true}, {'user' => u})
      get :show, params: {id: 'asdfasdf'}
      json = assert_success_json
      expect(json['tag']['id']).to eq(t2.global_id)
    end
  end

  describe 'update' do
    it 'should require an api token' do
      put :update, params: {id: 'asdf'}
      assert_missing_token
    end

    it 'should require a valid tag' do
      token_user
      put :update, params: {id: 'asdf'}
      assert_not_found('asdf')
    end

    it 'should require authorization' do
      u = User.create
      token_user
      t = NfcTag.process_new({}, {'user' => u})
      put :update, params: {id: t.global_id}
      assert_unauthorized
    end

    it 'should update the record' do
      token_user
      t = NfcTag.process_new({'label' => 'asdf'}, {'user' => @user})
      put :update, params: {id: t.global_id, tag: {'label' => 'qwer', 'public' => true}}
      json = assert_success_json
      expect(json['tag']['id']).to eq(t.global_id)
      expect(json['tag']['label']).to eq('qwer')
      expect(json['tag']['public']).to eq(true)
    end

    describe 'destroy' do
      it 'should require an api token' do
        delete :destroy, params: {id: 'asdf'}
        assert_missing_token
      end

      it 'should require a valid tag' do
        token_user
        delete :destroy, params: {id: 'asdf'}
        assert_not_found('asdf')
      end

      it 'should require authorization' do
        token_user
        u = User.create
        t = NfcTag.process_new({'label' => 'whatever'}, {'user' => u})
        delete :destroy, params: {id: t.global_id}
      end

      it 'should destroy the tag' do
        token_user
        t = NfcTag.process_new({'label' => 'whatever'}, {'user' => @user})
        delete :destroy, params: {id: t.global_id}
        json = assert_success_json
        expect(json['tag']['id']).to eq(t.global_id)
      end
    end
  end
end
