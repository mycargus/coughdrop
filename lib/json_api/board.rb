module JsonApi::Board
  extend ::NewRelic::Agent::MethodTracer
  extend JsonApi::Json
  
  TYPE_KEY = 'board'
  DEFAULT_PAGE = 25
  MAX_PAGE = 50
  
  def self.build_json(board, args={})
    json = {} #board.settings
    json['id'] = board.global_id
    json['key'] = board.key
    ['grid', 'name', 'description', 'image_url', 'buttons', 'stars', 'forks', 'word_suggestions', 'locale', 'home_board', 'categories'].each do |key|
      json[key] = board.settings[key]
    end
    list = [board.settings['locale'] || 'en']
    (board.settings['translations'] || {}).each{|k, h| if h.is_a?(Hash); list += h.keys; end }
    json['translated_locales'] = list.uniq
    self.trace_execution_scoped(['json/board/license']) do
      json['license'] = OBF::Utils.parse_license(board.settings['license'])
    end
    json['created'] = board.created_at.iso8601
    json['updated'] = board.settings['last_updated'] || board.updated_at.iso8601
    # TODO: check for updated/newly-added launch URLs for app-launching buttons
    # This checks for updated/newly-added launch URLs for previously-defined apps
    self.trace_execution_scoped(['json/board/apps']) do
      json['buttons'].each do |button|
        if button['apps']
          button['apps'] = AppSearcher.update_apps(button['apps'])
        end
      end
    end
    json['link'] = "#{JsonApi::Json.current_host}/#{board.key}"
    json['public'] = !!board.public
    json['visibility'] = board.public ? (board.fully_listed? ? 'public' : 'unlisted') : 'private'
    json['full_set_revision'] = board.full_set_revision
    json['current_revision'] = board.current_revision
    json['protected'] = !!board.protected_material?
    json['button_set_id'] = board.button_set_id
    json['brand_new'] = board.created_at < 1.hour.ago
    json['non_author_uses'] = board.settings['non_author_uses']
    json['total_buttons'] = board.settings['total_buttons']
    json['unlinked_buttons'] = board.settings['unlinked_buttons']
    json['downstream_boards'] = (board.settings['downstream_board_ids'] || []).length
    json['immediately_upstream_boards'] = (board.settings['immediately_upstream_board_ids'] || []).length
    json['user_name'] = board.cached_user_name
    self.trace_execution_scoped(['json/board/parent_board']) do
      json['parent_board_id'] = board.parent_board && board.parent_board.global_id
      json['parent_board_key'] = board.parent_board && board.parent_board.key
    end
    json['link'] = "#{JsonApi::Json.current_host}/#{board.key}"
    
    if args.key?(:permissions)
      self.trace_execution_scoped(['json/board/permissions']) do
        json['permissions'] = board.permissions_for(args[:permissions])
        json['starred'] = board.starred_by?(args[:permissions])
      end
    end
    
    if json['permissions'] && json['permissions']['edit']
      json['non_author_starred'] = board.non_author_starred?
      self.trace_execution_scoped(['json/board/share_users']) do
        shared_users = board.shared_users
        json['shared_users'] = shared_users
      end
    end
    if (json['permissions'] && json['permissions']['delete']) || (args[:permissions] && args[:permissions].allows?(args[:permissions], 'admin_support_actions'))
      json['downstream_board_ids'] = board.settings['downstream_board_ids']
      if args[:permissions] && args[:permissions].respond_to?(:settings)
        # TODO: sharding
        user_ids = UserBoardConnection.where(:board_id => board.id).map(&:user_id)
        user_names = User.where(:id => user_ids).select('id, user_name').map(&:user_name)
        valid_names = [args[:permissions].user_name] + (args[:permissions].settings['supervisees'] || []).map{|s| s['user_name'] }
        if args[:permissions].allows?(args[:permissions], 'admin_support_actions')
          valid_names = user_names
        end
        json['using_user_names'] = (user_names & valid_names).sort
      end
    end
    
    json
  end
  
  def self.extra_includes(board, json, args={})
    json['board']['protected_settings'] = board.settings['protected'] if board.protected_material?
    self.trace_execution_scoped(['json/board/images_and_sounds']) do
      hash = board.buttons_and_images_for(args[:permissions])
      json['images'] = hash['images']
      json['sounds'] = hash['sounds']
      json['board'] ||= {}
      json['board']['image_urls'] = {}
      json['board']['sound_urls'] = {}
      json['images'].each{|i| json['board']['image_urls'][i['id']] = i['url'] }
      json['sounds'].each{|i| json['board']['sound_urls'][i['id']] = i['url'] }
    end
    if args.key?(:permissions)
      json['board']['translations'] = board.settings['translations'] if board.settings['translations']
      self.trace_execution_scoped(['json/board/copy_check']) do
        copies = board.find_copies_by(args[:permissions])
        copy = copies[0]
        copy = nil if copy && (!args[:permissions] || copy.user_id != args[:permissions].id)
        if copy
          json['board']['copy'] = {
            'id' => copy.global_id,
            'key' => copy.key
          }
        end
        json['board']['copies'] = copies.count
      end
      self.trace_execution_scoped(['json/board/parent_board_check']) do
        parent = board.parent_board
        if parent
          json['board']['original'] = {
            'id' => parent.global_id,
            'key' => parent.key
          }
        end
      end
    end
    json
  end
end
