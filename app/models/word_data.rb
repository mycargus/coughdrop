class WordData < ActiveRecord::Base
  include SecureSerialize
  include Async
  secure_serialize :data
  replicated_model  
  before_save :generate_defaults
  
  def generate_defaults
    self.data ||= {}
  end
  
  def self.find_word(text, locale='en') 
    word = find_word_record(text, locale)
    word && word.data
  end
  
  def self.find_word_record(text, locale='en')
    return nil if text && text.match(/^[\+\:]/)
    locale ||= 'en'
    word = self.find_by(:word => text.downcase, :locale => locale)
    word ||= self.find_by(:word => text.downcase.gsub(/[^A-Za-z0-9'\s]/, ''), :locale => locale)
    if !word && locale.match(/-/)
      locale = locale.split(/-/)[0]
      word ||= self.find_by(:word => text.downcase, :locale => locale)
      word ||= self.find_by(:word => text.downcase.gsub(/[^A-Za-z0-9'\s]/, ''), :locale => locale)
    end
    word
  end
  
  def self.add_suggestion(word, sentence, locale='en')
    word = find_word_record(word, locale)
    return false unless word
    word.data['sentences'] ||= []
    word.data['sentences'] << {
      'sentence' => sentence,
      'approved' => true
    }
    word.data['sentences'].uniq!
    word.save
    true
  end
  
  def self.update_word_type(text, locale, type)
    wd = find_word_record(text, locale)
    locales = []
    raise "word not found" unless wd
    if wd.data['types']
      wd.data['types'] = ([type] + wd.data['types']).uniq
      wd.save
      locales << locale
    end
    (wd.data['translations'] || {}).each do |loc, str|
      trans = find_word_record(str, loc)
      if trans.data['types']
        trans.data['types'] = ([type] | trans.data['types']).uniq
        trans.save
        locales << loc
      end
    end
    locales
  end
  
  def self.translate(text, source_lang, dest_lang, type=nil)
    batch = translate_batch([{text: text, type: type}], source_lang, dest_lang)
    batch[:translations][text]
  end
  
  def self.translate_batch(batch, source_lang, dest_lang)
    res = {source: source_lang, dest: dest_lang, translations: {}}
    found = {}
    missing = batch
    batch.each do |obj|
      text = obj[:text]
      word = find_word_record(text, source_lang)
      new_text = nil
      if word && word.data
        word.data['translations'] ||= {}
        new_text ||= word.data['translations'][dest_lang]
        new_text ||= word.data['translations'][dest_lang.split(/-/)[0]]
      end
      if new_text
        res[:translations][text] = new_text
        missing = missing.select{|e| e[:text] != text }
      end
    end
    
    # API call to look up all missing strings
    query_translations(missing, source_lang, dest_lang).each do |obj|
      if obj[:translation]
        res[:translations][obj[:text]] = obj[:translation]
        schedule(:persist_translation, obj[:text], obj[:translation], source_lang, dest_lang, obj[:type])
      end
    end
    
    return res
  end
  
  def self.query_translations(words, source_lang, dest_lang)
    return [] unless ENV['GOOGLE_TRANSLATE_TOKEN']
    idx = 0
    res = []
    while idx < words.length
      list = words[idx, 20]
      # https://translation.googleapis.com/language/translate/v2?api_key=KEY&target=dest_lang
      strings = list.map{|obj| obj[:text] }
      key = ENV['GOOGLE_TRANSLATE_TOKEN']
      url = "https://translation.googleapis.com/language/translate/v2?key=#{key}&target=#{dest_lang}&source=#{source_lang}&format=text"
      url += '&' + strings.map{|str| "q=#{CGI.escape(str || '')}" }.join('&')
      data = Typhoeus.get(url)
      json = data && JSON.parse(data.body) rescue nil
      if json && json['data'] && json['data']['translations']
        json['data']['translations'].each_with_index do |trans, idx|
          obj = list[idx]
          if obj && trans['translatedText'] != obj[:text]
            obj[:translation] = trans['translatedText']
            res << obj
          end
        end
      end
      idx += 20
    end
    res
  end
  
  def self.persist_translation(text, translation, source_lang, dest_lang, type)
    # record the translations on the source word
    word = find_word_record(text, source_lang)
    word ||= WordData.new(:word => text.downcase.strip, :locale => source_lang, :data => {:word => text.downcase.strip})
    if word && word.data
      word.data['translations'] ||= {}
      word.data['translations'][dest_lang] ||= translation
      word.data['translations'][dest_lang.split(/-/)[0]] ||= translation
      word.save
    end
    # record the reverse translation on the 
    backwards_word = find_word_record(translation, dest_lang)
    backwards_word ||= WordData.new(:word => translation.downcase.strip, :locale => dest_lang, :data => {:word => translation.downcase.strip})
    if backwards_word && backwards_word.data
      backwards_word.data['translations'] ||= {}
      backwards_word.data['translations'][source_lang] ||= text
      backwards_word.data['translations'][source_lang.split(/-/)[0]] ||= text
      if type
        # TODO: right now this just assumes the first-translated is the most common usage for a homonym
        backwards_word.data['types'] ||= []
        backwards_word.data['types'] << type
        backwards_word.data['types'].uniq!
      end
      if word && word.data && word.data['types'] && word.data['types'][0]
        backwards_word.data['types'] ||= []
        backwards_word.data['types'] << word.data['types'][0]
        backwards_word.data['types'].uniq!
      end
      backwards_word.save
    end
  end
  
  def self.core_for?(word, user)
    self.core_list_for(user).map(&:downcase).include?(word.downcase.sub(/[^\w]+$/, ''))
  end
  
  def self.core_list_for(user)
    template = UserIntegration.find_by(:template => true, :integration_key => 'core_word_list')
    ui = template && UserIntegration.find_by(:template_integration => template, :user => user)
    if ui
      ui.settings['core_word_list']['words']
    else
      self.default_core_list
    end
  end
  
  def self.reachable_core_list_for(user)
    list = self.core_list_for(user)
    board_ids = []
    if user.settings['preferences'] && user.settings['preferences']['home_board']
      board_ids << user.settings['preferences']['home_board']['id']
    end
    board_ids += user.sidebar_boards.map{|b| b[:key] }
    boards = Board.find_all_by_path(board_ids).uniq
    
    button_sets = boards.map{|b| b.board_downstream_button_set }.compact.uniq
    reachable_words = button_sets.map{|bs| 
      bs.data['buttons'].map{|b| 
        if b['hidden']
          nil
        elsif b['linked_board_id'] && !b['link_disabled']
          nil
        else
          b['label'] || b['vocalization']
        end
      }.compact
    }.flatten.map{|w| w.downcase.sub(/[^\w]+$/, '') }.uniq
    res = []
    list.each do |word|
      res << word if reachable_words.include?(word.downcase.sub(/[^\w]+$/, ''))
    end
    res
  end
  
  def self.default_core_list
    @@default_core_list ||= nil
    return @@default_core_list if @@default_core_list
    lists = self.core_lists || []
    if lists
      @@default_core_list = lists[0]['words']
    end
    @@default_core_list ||= []
    @@default_core_list
  end
  
  # see also, http://praacticalaac.org/praactical/aac-vocabulary-lists/
  def self.core_lists
    @@core_lists ||= nil
    return @@core_lists if @@core_lists
    json = JSON.parse(File.read('./lib/core_lists.json')) rescue nil
    if json
      @@core_lists = json
    end
    @@core_lists ||= []
    @@core_lists
  end
  
  def self.import_suggestions
    suggestions = JSON.parse(File.read('./lib/core_suggestions.json')) rescue nil
    return false unless suggestions
    suggestions.each do |word, list|
      list.each do |idx, sentence|
        puts "#{word}: #{sentence}"
        WordData.add_suggestion(word, sentence)
      end
    end
    true
  end
end
