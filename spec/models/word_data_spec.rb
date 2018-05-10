require 'spec_helper'

RSpec.describe WordData, :type => :model do
  describe "find_word" do
    it "should find matching words" do
      WordData.create(:word => "troixlet", :locale => 'en', :data => {'a' => 'b'})
      WordData.create(:word => "runshkable", :locale => 'es', :data => {'b' => 'c'})
      expect(WordData.find_word('troixlet')).to eq({'a' => 'b'})
      expect(WordData.find_word('runshkable')).to eq(nil)
      expect(WordData.find_word('chuckxflem')).to eq(nil)
      expect(WordData.find_word('Troixlet')).to eq({'a' => 'b'})
      expect(WordData.find_word('Troixlet!!')).to eq({'a' => 'b'})
      expect(WordData.find_word('troixlet', 'es')).to eq(nil)
      expect(WordData.find_word('runshkable', 'es')).to eq({'b' => 'c'})
      expect(WordData.find_word('runshkABLE__', 'es')).to eq({'b' => 'c'})
      expect(WordData.find_word('runshkABLE ', 'es')).to eq(nil)
    end
  end
  
  describe "core_for" do
    it "should recognize core words for no user" do
      expect(WordData.core_for?("has", nil)).to eq(true)
      expect(WordData.core_for?("What", nil)).to eq(true)
      expect(WordData.core_for?("when?", nil)).to eq(true)
      expect(WordData.core_for?("that", nil)).to eq(true)
      expect(WordData.core_for?("always", nil)).to eq(true)
      expect(WordData.core_for?("bacon", nil)).to eq(false)
      expect(WordData.core_for?("asdf", nil)).to eq(false)
      expect(WordData.core_for?("awiulghuawihguwa", nil)).to eq(false)
      expect(WordData.core_for?("trinket", nil)).to eq(false)
    end
  end
  
  describe "generate_defaults" do
    it "should have generate defaults" do
      w = WordData.new
      w.generate_defaults
      expect(w.data).to eq({})
    end
  end
  
  describe "find_word_record" do
    it "should find the correct word" do
      a = WordData.create(:word => "troixlet", :locale => 'en', :data => {'a' => 'b'})
      b = WordData.create(:word => "runshkable", :locale => 'es', :data => {'b' => 'c'})
      expect(WordData.find_word_record('troixlet')).to eq(a)
      expect(WordData.find_word_record('runshkable')).to eq(nil)
      expect(WordData.find_word_record('chuckxflem')).to eq(nil)
      expect(WordData.find_word_record('Troixlet')).to eq(a)
      expect(WordData.find_word_record('Troixlet!!')).to eq(a)
      expect(WordData.find_word_record('troixlet', 'es')).to eq(nil)
      expect(WordData.find_word_record('runshkable', 'es')).to eq(b)
      expect(WordData.find_word_record('runshkABLE__', 'es')).to eq(b)
      expect(WordData.find_word_record('runshkABLE__', 'es-US')).to eq(b)
      expect(WordData.find_word_record('runshkABLE ', 'es')).to eq(nil)
    end
  end

  describe "translate" do
    it "should translate individual words" do
      expect(WordData).to receive(:query_translations).with([{:text => 'hat', :type => nil}], 'en', 'es').and_return([{:text => 'hat', :type => nil, :translation => 'cap'}])
      expect(WordData.translate('hat', 'en', 'es')).to eq('cap')
    end
    
    it "should persist found translations" do
      expect(WordData).to receive(:query_translations).with([{:text => 'hat', :type => nil}], 'en', 'es').and_return([{:text => 'hat', :type => nil, :translation => 'cap'}])
      expect(WordData.translate('hat', 'en', 'es')).to eq('cap')
      Worker.process_queues
      w = WordData.last
      expect(w.locale).to eq('es')
      expect(w.data).to eq({
        'word' => 'cap',
        'translations' => {'en' => 'hat'},
        'types' => ['noun']
      })
      w2 = WordData.where(:word => 'hat', :locale => 'en').first
      expect(w2).to_not eq(nil)
      expect(w2.data).to eq({
        'word' => 'hat',
        'translations' => {'es' => 'cap'},
        'types' => ['noun', 'verb', 'usu participle verb']
      })
    end
  end
  
  describe "query_translations" do
    it "should return an empty list of no search available" do
      ENV['GOOGLE_TRANSLATE_TOKEN'] = nil
      expect(Typhoeus).to_not receive(:get)
      res = WordData.query_translations([{text: 'hat'}], 'en', 'es')
      expect(res).to eq([])
    end
    
    it "should query translations" do
      ENV['GOOGLE_TRANSLATE_TOKEN'] = 'secrety'
      response = OpenStruct.new(body: {
        data: {
          translations: [
            {translatedText: 'top'},
            {translatedText: 'meow'}
          ]
        }
      }.to_json)
      expect(Typhoeus).to receive(:get).with('https://translation.googleapis.com/language/translate/v2?key=secrety&target=es&source=en&format=text&q=hat&q=cat').and_return(response)
      res = WordData.query_translations([{text: 'hat'}, {text: 'cat'}], 'en', 'es')
      expect(res).to eq([
        {text: 'hat', translation: 'top'},
        {text: 'cat', translation: 'meow'}
      ])
    end
    
    it "should only return results that have a translation" do
      ENV['GOOGLE_TRANSLATE_TOKEN'] = 'secrety'
      response = OpenStruct.new(body: {
        data: {
          translations: [
            {translatedText: 'top'},
            {translatedText: 'cat'}
          ]
        }
      }.to_json)
      expect(Typhoeus).to receive(:get).with('https://translation.googleapis.com/language/translate/v2?key=secrety&target=es&source=en&format=text&q=hat&q=cat').and_return(response)
      res = WordData.query_translations([{text: 'hat'}, {text: 'cat'}], 'en', 'es')
      expect(res).to eq([
        {text: 'hat', translation: 'top'}
      ])
    end
    
    it "should correct locale settings" do
      ENV['GOOGLE_TRANSLATE_TOKEN'] = 'secrety'
      response = OpenStruct.new(body: {
        data: {
          translations: [
            {translatedText: 'top'},
            {translatedText: 'cat'}
          ]
        }
      }.to_json)
      expect(Typhoeus).to receive(:get).with('https://translation.googleapis.com/language/translate/v2?key=secrety&target=zh-CN&source=en&format=text&q=hat&q=cat').and_return(response)
      res = WordData.query_translations([{text: 'hat'}, {text: 'cat'}], 'en_US', 'zh')
      expect(res).to eq([
        {text: 'hat', translation: 'top'}
      ])
    end
  end
  
  describe "translate_batch" do
    it "should translate a batch of words as well as possible" do
      a = WordData.create(:word => "troixlet", :locale => 'en', :data => {'a' => 'b', 'translations' => {'es' => 'trunket'}})
      b = WordData.create(:word => "runshkable", :locale => 'en', :data => {'a' => 'b', 'translations' => {'es-US' => 'rushef'}})
      expect(WordData).to receive(:query_translations).with([{:text => 'forshdeg'}, {:text => 'wilmerding'}], 'en', 'es-US').and_return([{:text => 'forshdeg', :type => nil, :translation => 'milnar'}])
      res = WordData.translate_batch([
        {:text => 'troixlet'},
        {:text => 'runshkable'},
        {:text => 'forshdeg'},
        {:text => 'wilmerding'}
      ], 'en', 'es-US')
      expect(res[:source]).to eq('en')
      expect(res[:dest]).to eq('es-US')
      expect(res[:translations]).to eq({
        'troixlet' => 'trunket',
        'runshkable' => 'rushef',
        'forshdeg' => 'milnar'
      })
    end
  end

  describe "persist_translation" do
    it "should persist translations correctly" do
      b = WordData.create(:word => "runshkable", :locale => 'en', :data => {'a' => 'b', 'types' => ['something']})
      w = WordData.create(:word => 'railymop', :locale => 'es', :data => {'types' => ['verb']})
      WordData.persist_translation('runshkable', 'railymop', 'en', 'es-US', 'noun')
      expect(WordData.find_word_record('runshkable', 'en')).to eq(b)
      b.reload
      expect(b.data['translations']).to eq({'es' => 'railymop', 'es-US' => 'railymop'})
      w1 = WordData.find_word_record('railymop', 'es')
      expect(w1).to eq(w)
      expect(w1).to_not eq(nil)
      expect(w1.data['translations']).to eq({'en' => 'runshkable'})
      expect(w1.data['types']).to eq(['verb', 'noun', 'something'])
    end

    it "should use the original word type if needed as fallback" do
      b = WordData.create(:word => "runshkable", :locale => 'en', :data => {'a' => 'b', 'types' => ['something']})
      WordData.persist_translation('runshkable', 'railymop', 'en', 'es-US', nil)
      expect(WordData.find_word_record('runshkable', 'en')).to eq(b)
      b.reload
      expect(b.data['translations']).to eq({'es' => 'railymop', 'es-US' => 'railymop'})
      
      w1 = WordData.find_word_record('railymop', 'es-US')
      expect(w1).to_not eq(nil)
      expect(w1.data['translations']).to eq({'en' => 'runshkable'})
      expect(w1.data['types']).to eq(['something'])
    end
  end
  
  describe "core_list_for" do
    it "should return the default core list" do
      expect(WordData).to receive(:default_core_list).and_return('list!');
      expect(WordData.core_list_for(nil)).to eq('list!')
    end
    
    it "should return a user's personalized list" do
      t = UserIntegration.create(:template => true, :integration_key => 'core_word_list')
      u = User.create
      ui = UserIntegration.create(:user => u, :template_integration_id => t.id)
      ui.settings['core_word_list'] = {'id' => 'bacon', 'words' => ['a', 'b', 'c', 'd']}
      ui.save
      expect(WordData.core_list_for(u)).to eq(['a', 'b', 'c', 'd'])
    end
  end
  
  describe "reachable_core_list_for" do
    it "should return a list of words" do
      u = User.create
      b = Board.create(:user => u)
      b.process({
        'buttons' => [
          {'id' => 1, 'label' => 'you'},
          {'id' => 2, 'label' => 'he'},
          {'id' => 3, 'label' => 'I'},
          {'id' => 4, 'label' => 'like'},
          {'id' => 5, 'label' => 'snooze'},
          {'id' => 6, 'label' => 'pretend'},
          {'id' => 7, 'label' => 'wonder'},
          {'id' => 8, 'label' => 'think'},
          {'id' => 9, 'label' => 'favorite'},
        ]
      })
      u.settings['preferences']['home_board'] = {'id' => b.global_id, 'key' => b.key}
      u.save
      Worker.process_queues
      Worker.process_queues
      expect(WordData.reachable_core_list_for(u)).to eq(["i", "you", "like", "he", "think", "favorite", "pretend"])
    end
    
    it "should return words available from the root board" do
      u = User.create
      b = Board.create(:user => u)
      b.process({
        'buttons' => [
          {'id' => 1, 'label' => 'you'},
          {'id' => 2, 'label' => 'he'},
          {'id' => 3, 'label' => 'I'},
          {'id' => 4, 'label' => 'like'},
          {'id' => 5, 'label' => 'snooze'},
          {'id' => 6, 'label' => 'pretend'},
          {'id' => 7, 'label' => 'wonder'},
          {'id' => 8, 'label' => 'think'},
          {'id' => 9, 'label' => 'favorite'},
        ]
      })
      u.settings['preferences']['home_board'] = {'id' => b.global_id, 'key' => b.key}
      u.save
      Worker.process_queues
      Worker.process_queues
      expect(WordData.reachable_core_list_for(u)).to eq(["i", "you", "like", "he", "think", "favorite", "pretend"])
    end
    
    it "should return words available from the sidebar" do
      u = User.create
      b = Board.create(:user => u)
      b.process({
        'buttons' => [
          {'id' => 1, 'label' => 'yes'},
          {'id' => 2, 'label' => 'no'},
          {'id' => 3, 'label' => 'I'},
          {'id' => 4, 'label' => 'like'},
          {'id' => 5, 'label' => 'snooze'},
          {'id' => 6, 'label' => 'pretend'},
          {'id' => 7, 'label' => 'wonder'},
          {'id' => 8, 'label' => 'think'},
          {'id' => 9, 'label' => 'favorite'},
        ]
      })
      u.settings['preferences']['home_board'] = {'id' => b.global_id, 'key' => b.key}
      u.save
      Worker.process_queues
      Worker.process_queues
      expect(WordData.reachable_core_list_for(u)).to eq(["i", "like", "no", "yes", "think", "favorite", "pretend"])
    end
    
    it "should not return words that aren't accessible, even if they're core words" do
      u = User.create
      b = Board.create(:user => u)
      b.process({
        'buttons' => [
          {'id' => 1, 'label' => 'you'},
          {'id' => 2, 'label' => 'bacon'},
          {'id' => 3, 'label' => 'radish'},
          {'id' => 4, 'label' => 'like'},
          {'id' => 5, 'label' => 'snooze'},
          {'id' => 6, 'label' => 'watercolor'},
          {'id' => 7, 'label' => 'wonder'},
          {'id' => 8, 'label' => 'splendid'},
          {'id' => 9, 'label' => 'favorite'},
        ]
      })
      u.settings['preferences']['home_board'] = {'id' => b.global_id, 'key' => b.key}
      u.save
      Worker.process_queues
      Worker.process_queues
      expect(WordData.reachable_core_list_for(u)).to eq(["you", "like", "favorite"])
    end
  end
  
  describe "add_suggestion" do
    it "should return false on missing word" do
      expect(WordData.add_suggestion('awgoawtiawt', 'this is a good one', 'bleh')).to eq(false)
    end
    
    it "should add the sentence" do
      res = WordData.add_suggestion('hat', 'I like my hat', 'en')
      expect(res).to eq(true)
      word = WordData.find_word('hat')
      expect(word['sentences']).to eq([{'sentence' => 'I like my hat', 'approved' => true}])
    end
  end
  
  describe "core_and_fringe_for" do
    it "should include core and fringe lists" do
      u = User.create
      expect(WordData).to receive(:core_list_for).with(u).and_return(['a'])
      expect(WordData).to receive(:reachable_core_list_for).with(u, []).and_return(['b'])
      expect(WordData).to receive(:fringe_list_for).with(u, []).and_return(['c'])
      expect(WordData).to receive(:requested_phrases_for).with(u, []).and_return(['d'])
      expect(WordData.core_and_fringe_for(u)).to eq({
        :for_user => ['a'],
        :reachable_for_user => ['b'],
        :reachable_fringe_for_user => ['c'],
        :requested_phrases_for_user => ['d']
      })
    end
  end

  describe "requested_phrases_for" do
    it "should return a list with used buttons marked" do
      bs = BoardDownstreamButtonSet.new(:data => {
        'buttons' => [
          {'label' => 'hipster'},
          {'label' => 'hippie'},
          {'label' => 'hippo', 'hidden' => true},
          {'label' => 'hipchat', 'linked_board_id' => 'asdf', 'link_disabled' => true},
          {'label' => 'hipmonk', 'linked_board_id' => 'asdf'}
        ]
      })
      u = User.new(:settings => {
        'preferences' => {
          'requested_phrases' => [
            'hippie', 'hippo', 'hipchat', 'hipmonk'
          ]
        }
      })
      expect(WordData.requested_phrases_for(u, [bs])).to eq([
        {text: 'hippie', used: true},
        {text: 'hippo'},
        {text: 'hipchat', used: true},
        {text: 'hipmonk'}
      ])
    end
  end
  
  describe "fringe_lists" do
    it "should return a list of lists" do
      expect(WordData.fringe_lists[0]['id']).to eq('common_fringe')
    end
  end
 
  describe "fringe_list_for" do
    it "should return only accessible fringe words" do
      u = User.create
      b1 = Board.create(:user => u)
      b1.settings['buttons'] = [{'id' => 1, 'label' => 'pizza'}]
      b1.save
      b2 = Board.create(:user => u)
      b2.settings['buttons'] = [{'id' => 2, 'label' => 'flower'}, {'id' => 3, 'label' => 'rose'}, {'id' => 4, 'label' => 'where'}]
      b2.save
      
      u.settings['preferences']['home_board'] = {'id' => b1.global_id, 'key' => b1.key}
      u.settings['preferences']['sidebar_boards'] = [{'key' => b2.key}]
      u.save
      BoardDownstreamButtonSet.update_for(b1.global_id)
      BoardDownstreamButtonSet.update_for(b2.global_id)
      expect(u.sidebar_boards).to eq([{'key' => b2.key}])
      expect(BoardDownstreamButtonSet.for_user(u).map(&:board_id).sort).to eq([b1.id, b2.id].sort)
      expect(WordData.fringe_list_for(u)).to eq([
        "pizza", "flower", "rose"
      ])
    end
  end
  
  describe "message_bank_suggestions" do
    it "should return a list" do
      expect(WordData.message_bank_suggestions.length).to be > 0
      expect(WordData.message_bank_suggestions[0]['id']).to eq('boston_childrens')
    end
  end
  
  describe "standardized_words" do
    it 'should return a hash of words' do
      expect(WordData.standardized_words['this']).to eq(true)
      expect(WordData.standardized_words['golem']).to eq(nil)
    end
  end
  
  describe "basic_core_for" do
    it "should have specs" do
      write_this_test
    end
  end
  
  describe "activities_for" do
    it "should have specs" do
      write_this_test
    end
  end
  
  describe "update_activities_for" do
    it "should have specs" do
      write_this_test
    end
  end
end
