class BoardDownstreamButtonSet < ActiveRecord::Base
  MAX_DEPTH = 10
  include Async
  include GlobalId
  include SecureSerialize
  secure_serialize :data
  belongs_to :board
  replicated_model

  before_save :generate_defaults
  
  def generate_defaults
    self.data ||= {}
    self.data['buttons'] ||= []
    self.data['board_ids'] = self.data['buttons'].map{|b| b['board_id'] }.compact.uniq
    self.data['button_count'] = self.data['buttons'].length
    self.data['board_count'] = self.data['buttons'].map{|b| b['board_id'] }.uniq.length
    self.data.delete('json_response')
  end
  
  def cached_json_response
    self.data && self.data['json_response']
  end
  
  def self.for_user(user)
    board_ids = []
    if user.settings['preferences'] && user.settings['preferences']['home_board']
      board_ids << user.settings['preferences']['home_board']['id']
    end
    board_ids += user.sidebar_boards.map{|b| b[:key] }
    boards = Board.find_all_by_path(board_ids).uniq
    
    button_sets = boards.map{|b| b.board_downstream_button_set }.compact.uniq
  end
  
  def self.update_for(board_id)
    board = Board.find_by_global_id(board_id)
    if board
      set = BoardDownstreamButtonSet.find_or_create_by(:board_id => board.id) rescue nil
      set ||= BoardDownstreamButtonSet.find_or_create_by(:board_id => board.id)
      boards_hash = {}
      Board.find_all_by_global_id(board.settings['downstream_board_ids'] || []).each do |brd|
        boards_hash[brd.global_id] = brd
      end
      
      boards_to_visit = [{:board => board, :depth => 0, :index => 0}]
      visited_board_ids = []
      linked_board_ids = []
      all_buttons = []
      while boards_to_visit.length > 0
        bv = boards_to_visit.shift
        board_to_visit = bv[:board]
        images = board_to_visit.button_images
        visited_board_ids << board_to_visit.global_id
        # add all buttons
        board_to_visit.settings['buttons'].each_with_index do |button, idx|
          image = images.detect{|i| button['image_id'] == i.global_id }
          button_data = {
            'id' => button['id'],
            'locale' => board_to_visit.settings['locale'] || 'en',
            'board_id' => board_to_visit.global_id,
            'board_key' => board_to_visit.key,
            'hidden' => !!button['hidden'],
            'image' => image && image.url,
            'sound_id' => button['sound_id'],
            'label' => button['label'],
            'vocalization' => button['vocalization'],
            'link_disabled' => !!button['link_disabled'],
            'depth' => bv[:depth] || 0
          }
          # check for any linked buttons
          if button['load_board'] && button['load_board']['id']
            linked_board = boards_hash[button['load_board']['id']]
            linked_board ||= Board.find_by_global_id(button['load_board']['id'])
            if linked_board
              button_data['linked_board_id'] = linked_board.global_id
              button_data['linked_board_key'] = linked_board.key
            end
            # mark the first link to each board as "preferred"
            # TODO: is this a good idea? is there a better strategy? It honestly
            # shouldn't happen that much, having multiple links to the same board
            if linked_board && !linked_board_ids.include?(linked_board.global_id) && !button['hidden'] && !button['link_disabled']
              button_data['preferred_link'] = true
              linked_board_ids << button['load_board']['id']
              boards_to_visit << {:board => linked_board, :depth => bv[:depth] + 1, :index => idx} if !visited_board_ids.include?(linked_board.global_id)
            end
          end
          all_buttons << button_data
        end
        boards_to_visit.sort_by!{|bv| [bv[:depth], bv[:index]] }
      end
      set.data['buttons'] = all_buttons
      set.save
      if board.settings['board_downstream_button_set_id'] != set.global_id
        # TODO: race condition?
        board.update_setting('board_downstream_button_set_id', set.global_id)
      end
      set
    end
  end
end
