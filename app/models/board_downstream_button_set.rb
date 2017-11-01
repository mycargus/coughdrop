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
    @buttons = nil
    self.data['board_ids'] = self.buttons.map{|b| b['board_id'] }.compact.uniq
    self.data['linked_board_ids'] = self.buttons.map{|b| b['linked_board_id'] }.compact.uniq
    self.data['button_count'] = self.buttons.length
    self.data['board_count'] = self.buttons.map{|b| b['board_id'] }.uniq.length
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
    board_ids += user.sidebar_boards.map{|b| b['key'] }
    boards = Board.find_all_by_path(board_ids).uniq
    
    button_sets = boards.map{|b| b.board_downstream_button_set }.compact.uniq
  end
  
  def buttons
    return @buttons if @buttons
    if self.data['source_id']
      bs = BoardDownstreamButtonSet.find_by_global_id(self.data['source_id'])
      if bs
        @buttons = bs.buttons_starting_from(self.related_global_id(self.board_id))
        return @buttons
      end
    end
    if self.data['buttons']
      @buttons = self.data['buttons']
    else
      @buttons = []
    end
  end
  
  def buttons_starting_from(board_id)
    boards_to_include = {}
    boards_to_include[board_id] = true
    res = []
    (self.data['buttons'] || []).each do |button|
      if boards_to_include[button['board_id']]
        if button['linked_board_id']
          boards_to_include[button['linked_board_id']] = true
        end
      end
    end
    (self.data['buttons'] || []).each do |button|
      if boards_to_include[button['board_id']]
        res << button
      end
    end
    res
  end
  
  def self.update_for(board_id)
    board = Board.find_by_global_id(board_id)
    if board
      set = BoardDownstreamButtonSet.find_or_create_by(:board_id => board.id) rescue nil
      set ||= BoardDownstreamButtonSet.find_or_create_by(:board_id => board.id)
      
      existing_board_ids = (set.data || {})['linked_board_ids'] || []
      
      Board.find_all_by_global_id(board.settings['immediately_upstream_board_ids'] || []).each do |brd|
        set.data['found_upstream_board'] = true
        bs = brd.board_downstream_button_set
        set.data['found_upstream_set'] = !!bs
        linked_board_ids = bs.data['linked_board_ids'] || brd.buttons.map{|b| b['linked_board_id'] }.compact.uniq
        if bs && bs.data['buttons'] && linked_board_ids.include?(board.global_id)
          set.data['source_id'] = bs.global_id
          set.data['buttons'] = nil
          set.save
          return set
        elsif bs && bs.data['source_id'] && linked_board_ids.include?(board.global_id)
          set.data['source_id'] = bs.data['source_id']
          set.data['buttons'] = nil
          set.save
          return set
        end
      end
      
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
            'hidden_link' => !!bv[:hidden],
            'image' => image && image.url,
            'image_id' => button['image_id'],
            'sound_id' => button['sound_id'],
            'label' => button['label'],
            'force_vocalize' => button['add_to_vocalization'],
            'vocalization' => button['vocalization'],
            'link_disabled' => !!button['link_disabled'],
            'border_color' => button['border_color'],
            'background_color' => button['background_color'],
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
              boards_to_visit << {:board => linked_board, :depth => bv[:depth] + 1, :hidden => (bv[:hidden] || button['hidden'] || button['link_disabled']), :index => idx} if !visited_board_ids.include?(linked_board.global_id)
            end
          end
          all_buttons << button_data
        end
        boards_to_visit.sort_by!{|bv| [bv[:depth], bv[:index]] }
      end
      set.data['buttons'] = all_buttons
      set.data['source_id'] = nil
      set.save
      lost_board_ids = existing_board_ids - set.data['linked_board_ids']
      lost_board_ids.each do |id|
        BoardDownstreamButtonSet.schedule_once(:update_for, id)
      end
      if board.settings['board_downstream_button_set_id'] != set.global_id
        # TODO: race condition?
        board.update_setting('board_downstream_button_set_id', set.global_id)
      end
      set
    end
  end
  
  def self.spoken_button?(button, user)
    if !button['hidden']
      if !button['linked_board_id'] || (user && user.settings['preferences']['vocalize_linked_buttons']) || button['force_vocalize']
        if button['label'] && button['label'].split(/\s/).length <= 2
          return true
        end
      end
    end
    false
  end
  
  def self.word_map_for(user)
    board_key = user && user.settings['preferences'] && user.settings['preferences']['home_board'] && user.settings['preferences']['home_board']['key']
    board = Board.find_by_path(board_key) if board_key
    button_set = board && board.board_downstream_button_set
    return nil unless button_set
    res = {'words' => [], 'word_map' => {}}
    
    # TODO: include images with attribution
    
    button_set.buttons.each do |button|
      if spoken_button?(button, user)
        res['words'] << button['label'].downcase
        locale = button['locale'] || 'en'
        res['word_map'][locale] ||= {}
        res['word_map'][locale][button['label'].downcase] = {
          'label' => button['label'].downcase,
          'border_color' => button['border_color'],
          'background_color' => button['background_color'],
          'image' => {
            'image_url' => button['image'],
            'license' => 'private'
          }
        }
      end
    end
    res['words'].uniq!
    
    res
  end
end
