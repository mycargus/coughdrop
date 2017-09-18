module JsonApi::ButtonSet
  extend JsonApi::Json
  
  TYPE_KEY = 'buttonset'
  DEFAULT_PAGE = 1
  MAX_PAGE = 1
  
  def self.build_json(button_set, args={})
    board = button_set.board
    json = {}
    if board
      json['id'] = board.global_id
      json['key'] = board.key
      json['name'] = board.settings && board.settings['name']
      json['full_set_revision'] = board.full_set_revision
    end
    
    json['buttons'] = {}.merge(button_set.data['buttons'])
    json['buttons'].each{|b| b['image'] = Uploader.fronted_url(b['image']) if b['image'] }

    board_ids = button_set.data['board_ids'] || button_set.data['buttons'].map{|b| b['board_id'] }.uniq
    
    # TODO: sharding
    allowed_ids = {}
    Board.where(:id => Board.local_ids(board_ids), :public => true).select('id').each do |b|
      allowed_ids[b.global_id] = true
    end
    # TODO: should site admins have access to all boards?
    allowed_ids[board.global_id] = true if board
    if args[:permissions]
      args[:permissions].private_viewable_board_ids.each do |id|
        allowed_ids[id] = true
      end
    end
    
    json['buttons'] = json['buttons'].select{|b| allowed_ids[b['board_id']] }
    json['board_ids'] = json['buttons'].map{|b| b['board_id'] }.compact.uniq

    json
  end
end
