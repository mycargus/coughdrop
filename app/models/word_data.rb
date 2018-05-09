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
  
  def self.add_activities_for(user, hash)
    return true if !user.full_premium?
    act = (user.settings['target_words'] || {})['activities'] || {}
    fresh = true
    hash['generated'] = [hash['generated'], act['generated'] || Time.at(0).iso8601].compact.min
    (act['words'] || []).each do |word|
      existing = hash['words'].detect{|w| w['word'] == word['word'] && w['locale'] == word['locale'] }
      if existing
        existing['user_ids'] << user.global_id
      else
        word['user_ids'] = [user.global_id]
        hash['words'] << word
      end
    end
    (act['list'] || []).each do |sug|
      existing = hash['list'].detect{|s| s['id'] == sug['id']}
      if existing
        existing['score'] += sug['score']
        existing['user_ids'] << user.global_id
      else
        sug['user_ids'] = [user.global_id]
        hash['list'] << sug
      end
    end
    # If the target word list has updated more recently than the activity list, then
    # the activity list is out of date
    if user.settings['target_words'] && act['generated'] && user.settings['target_words']['generated'] > act['generated']
      fresh = false
    end

    fresh
  end
  
  def self.activities_for(user, include_supervisees=false)
    res = {
      'words' => [],
      'list' => [],
      'checked' => Time.now.iso8601
    }
    all_fresh = add_activities_for(user, res)
    if include_supervisees
      user.supervisees.each do |sup|
        all_fresh = all_fresh && add_activities_for(sup, res)
      end
    end
    res['list'] = res['list'].sort_by{|s| [s['score'], rand] }.reverse
    # If all the activity lists are more recent than the word lists they were derived
    # from, and all the activity lists were generated no less than two weeks ago,
    # then mark this list as fresh.
    res.instance_variable_set('@fresh', !!(all_fresh && res['generated'] && res['generated'] > 2.weeks.ago.iso8601))
#    res.instance_variable_set('@fresh', true) if !user.settings['target_words']
    res
  end
  
  def self.update_activities_for(user_id, include_supervisees=false)
    user = User.find_by_global_id(user_id)
    return nil unless user

    if !user.settings['target_words']
      user.settings['target_words'] = {
        'generated' => Time.now.iso8601,
        'list' => []
      }
    end
    
    if include_supervisees
      user.supervisees.each{|u| WordData.update_activities_for(u.global_id, false) }
    end
    
    # short-circuit if recently-generated
    activities_session = LogSession.find_by(log_type: 'activities', user_id: user.id)
    existing = activities_for(user, include_supervisees)
    if existing.instance_variable_get('@fresh') && existing['words'].length >= 3
      generated = Time.parse(existing['generated'])
      # TODO: created_at will tell us if a new goal was created, but not if it was just modified
      # and updated_at also gets modified regularly when goals have a badges attached, even
      # if they haven't actually been modified.
      more_recent_goals = UserGoal.where(active: true, user_id: user.id).where(['created_at > ?', generated]).count
      more_recent_activities = activities_session && activities_session.updated_at > generated
      return existing unless more_recent_goals || more_recent_activities
    end
    
    # get the user's suggested words
    lists = self.core_and_fringe_for(user)
    available_words = lists[:reachable_for_user] + lists[:reachable_fringe_for_user]
    basic_core = self.basic_core_list

    suggestions = []
    suggestions += ((user.settings['target_words'] || {})['list'] || []).select{|w| available_words.include?(w['word']) }
    if suggestions.length < 3
      # add from the basic word list, indexed by weeks having daily_use or created_at
      daily_use = LogSession.find_by(log_type: 'daily_use', user_id: user.id)
      units = ((Time.now - user.created_at) / 1.day) / 10
      if daily_use
        units = (daily_use.data['days'] || []).keys.length / 5
      end
      index = [0, units % (basic_core.length - 5)].max
      basic_core[index, 5].each do |word|
        if !suggestions.detect{|w| w['word'] == word }
          suggestions << {
            'word' => word,
            'locale' => 'en', # TODO: i18n
            'reasons' => ['fallback']
          }
        end
      end
    end
    
    # make an API call to comm workshop to get activities for the words
    activities = []
    found_words = []
    word_re = Regexp.new("\\b(" + suggestions.map{|s| s['word'] }.join('|') + ")\\b")
    quote_re = Regexp.new("\"(" + suggestions.map{|s| s['word'] }.join('|') + ")\"")
    suggestions.each_with_index do |suggestion, idx|
      next if found_words.length > 5
      word = suggestion['word']
      next unless available_words.include?(word)
      locale = suggestion['locale'] || 'en'
      req = Typhoeus.get("https://workshop.openaac.org/api/v1/words/#{CGI.escape(word + ":" + locale)}")
      json = JSON.parse(req.body) rescue nil
      word = json && json['word']
      if word && !word['pending']
        found_words << {
          'word' => word['word'],
          'locale' => word['locale'],
          'reasons' => suggestion['reasons']
        }
        ['learning_projects', 'activity_ideas', 'topic_starters', 'books', 'videos', 'send_homes'].each do |key|
          list = (word[key] || [])
          list.each do |a|
            a['type'] = key
            a['word'] = suggestion['word']
            a['locale'] = locale
            a['score'] = 5 * (suggestions.length - idx) / suggestions.length.to_f
            a['score'] += 1 if ['learning_projects', 'activity_ideas', 'send_homes'].include?(key)
            text = "#{suggestion['text']} #{suggestion['description']}"
            a['score'] += 0.3 * text.scan(word_re).length
            a['score'] += 0.5 * text.scan(quote_re).length
          end
          activities += list
        end
      end
    end
    # TODO: boost activities that:
    # - have multiple words from the suggestion list
    # - represent an actual activity
    # - have more user likes
    # - match the type the user usually implements
    # - come from the same author as previous successful activities
    # - does not come from authors of previous flopped activities
    
    # mark which activities have been used (and how recently) by the user
    if activities_session && activities_session.data['activities']
      activities.each do |a|
        if activities_session.data['activities'][a['id']]
          ref = activities_session.data['activities'][a['id']]
          # Have a weighted history so after like a year there's little discount for
          # having been tried already
          a['handled'] = ref['updated']
          a['attempted'] = false
          a['skipped'] = true
        end
      end
    end
    
    # prioritize based on activities that have words in the user's vocab?
    available_words.include?('')
    activities.each do |a|
      # TODO: ...
      # a['score'] += extra_words_in(a, available_words)
    end
    
    # add the activities to the user object for quick retrieval
    user.settings['target_words']['activities'] = {
      'generated' => Time.now.iso8601,
      'words' => found_words,
      'list' => activities.sort_by{|a| [a['score'] || 0, rand] }.reverse[0, 25]
    }
    user.save
    
    activities_for(user, include_supervisees)
  end
  
# word types:
#  'noun', 'plural noun', 'noun phrase',
#  'verb', 'usu participle verb', 'transitive verb', 'intransitive verb',
#  'adjective',
#  'adverb',
#  'conjunction',
#  'preposition',
#  'interjection',
#  'pronoun',
#  'article', 'definite article', 'indefinite article',
#  'nominative'
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

      langs = {source: source_lang, dest: dest_lang}
      langs.each do |key, val|
        if val.match(/zh_Hans/)
          langs[key] = 'zh-CN'
        elsif val.match(/zh_Hant/)
          langs[key] = 'zh-TW'
        elsif val.match(/zh/)
          langs[key] = 'zh-CN'
        elsif val.match(/[_-]/)
          langs[key] = val.split(/[_-]/)[0].downcase
        end
      end
      source_lang = langs[:source]
      dest_lang = langs[:dest]

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
  
  def self.core_and_fringe_for(user)
    res = {}
    res[:for_user] = WordData.core_list_for(user)
    button_sets = BoardDownstreamButtonSet.for_user(user)
    res[:reachable_for_user] = WordData.reachable_core_list_for(user, button_sets)
    res[:reachable_fringe_for_user] = WordData.fringe_list_for(user, button_sets)
    res[:requested_phrases_for_user] = WordData.requested_phrases_for(user, button_sets)
    res
  end
  
  def self.core_list_for(user)
    template = user && UserIntegration.find_by(:template => true, :integration_key => 'core_word_list')
    ui = template && UserIntegration.find_by(:template_integration => template, :user => user)
    if ui
      ui.settings['core_word_list']['words']
    else
      self.default_core_list
    end
  end
  
  def self.basic_core_list_for(user)
    self.basic_core_list[0, 25]
  end
  
  def self.requested_phrases_for(user, button_sets)
    phrases = (user.settings && user.settings['preferences'] && user.settings['preferences']['requested_phrases']) || []
    button_sets ||= BoardDownstreamButtonSet.for_user(user)
    res = []
    words = {}
    button_sets.each do |bs|
      bs.buttons.each do |b| 
        if b['hidden']
          nil
        elsif b['linked_board_id'] && !b['link_disabled']
          nil
        else
          if b['label'] || b['vocalization']
            words[(b['label'] || b['vocalization']).downcase.sub(/[^\w]+$/, '')] = true
          end
        end
      end
    end
    phrases.each do |str|
      word = {text: str}
      if words[str.downcase.sub(/[^\w]+$/, '')]
        word[:used] = true
      end
      res << word
    end
    res
  end
  
  def self.fringe_list_for(user, button_sets=nil)
    list = self.fringe_lists[0]
    button_sets ||= BoardDownstreamButtonSet.for_user(user)
    res = []
    words = {}
    button_sets.each do |bs| 
      bs.buttons.each do |b| 
        if b['hidden']
          nil
        elsif b['linked_board_id'] && !b['link_disabled']
          nil
        else
          if b['label'] || b['vocalization']
            words[(b['label'] || b['vocalization']).downcase.sub(/[^\w]+$/, '')] = true
          end
        end
      end
    end
    list['categories'].each do |category|
      category['words'].each do |word|
        if words[word.downcase.sub(/[^\w]+$/, '')]
          res << word
        end
      end
    end
    res.uniq
  end
  
  def self.reachable_core_list_for(user, button_sets=nil)
    list = self.core_list_for(user)
    button_sets ||= BoardDownstreamButtonSet.for_user(user)
    reachable_words = button_sets.map{|bs| 
      bs.buttons.map{|b| 
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

  def self.basic_core_list
    @@basic_core_list ||= nil
    return @@basic_core_list if @@basic_core_list
    lists = self.core_lists || []
    if lists
      @@basic_core_list = (lists.detect{|l| l['id'] == 'basic_core'} || {})['words']
    end
    @@basic_core_list ||= []
    @@basic_core_list
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
  
  def self.fringe_lists
    @@fringe_lists ||= nil
    return @@fringe_lists if @@fringe_lists
    json = JSON.parse(File.read('./lib/fringe_suggestions.json')) rescue nil
    if json
      @@fringe_lists = json
    end
    @@fringe_lists ||= []
    @@fringe_lists
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
  
  def self.standardized_words
    @@standardized_words ||= nil
    return @@standardized_words if @@standardized_words
    hash = {}
    (self.core_lists || []).each do |list|
      (list['words'] || []).each do |word|
        hash[word] = true
      end
    end
    @@standardized_words = hash
    @@standardized_words
  end
  
  def self.message_bank_suggestions
    @@message_bank_suggestions ||= nil
    return @@message_bank_suggestions if @@message_bank_suggestions
    json = JSON.parse(File.read('./lib/message_bank_suggestions.json')) rescue nil
    if json
      @@message_bank_suggestions = json
    end
    @@message_bank_suggestions ||= []
    @@message_bank_suggestions
  end
end
