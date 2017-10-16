module Relinking
  extend ActiveSupport::Concern
  
  def links_to?(board)
    (self.settings['buttons'] || []).each do |button|
      if button['load_board'] && button['load_board']['id'] == board.global_id
        return true
      end
    end
    false
  end
  
  def for_user?(user)
    user && self.user_id == user.id
  end
  
  def just_for_user?(user)
    return !self.public && self.for_user?(user) && !self.shared_by?(user)
  end
  
  def copy_for(user, make_public=false, copy_id=nil)
    return nil unless user
    board = Board.new(:user_id => user.id, :parent_board_id => self.id)
    board.key = board.generate_board_key(self.key.split(/\//)[1])
    board.settings['copy_id'] = copy_id
    board.settings['name'] = self.settings['name']
    board.settings['description'] = self.settings['description']
    board.settings['image_url'] = self.settings['image_url']
    board.settings['locale'] = self.settings['locale']
    board.settings['translations'] = self.settings['translations']
    board.settings['buttons'] = self.settings['buttons']
    board.settings['license'] = self.settings['license']
    board.settings['grid'] = self.settings['grid']
    board.settings['never_edited'] = true
    board.public = true if make_public
    board.save!
    board
  end
  
  def replace_links!(old_board, new_board)
    (self.settings['buttons'] || []).each_with_index do |button, idx|
      if button['load_board'] && button['load_board']['id'] == old_board.global_id
        self.settings['buttons'][idx]['load_board']['id'] = new_board.global_id
        self.settings['buttons'][idx]['load_board']['key'] = new_board.key
      end
    end
    self.save
  end

  module ClassMethods
    def replace_board_for(user, opts)
      auth_user = opts[:authorized_user]
      starting_old_board = opts[:starting_old_board] || raise("starting_old_board required")
      starting_new_board = opts[:starting_new_board] || raise("starting_new_board required")
      update_inline = opts[:update_inline] || false
      make_public = opts[:make_public] || false
      board_ids = []
      # get all boards currently connected to the user
      if user.settings['preferences'] && user.settings['preferences']['home_board']
        board_ids += [user.settings['preferences']['home_board']['id']] 
        board = Board.find_by_path(user.settings['preferences']['home_board']['id'])
        board.track_downstream_boards!
        downstream_ids = board.settings['downstream_board_ids']
        if opts[:valid_ids]
          downstream_ids = downstream_ids & opts[:valid_ids]
        end
        board_ids += downstream_ids
      end
      boards = Board.find_all_by_path(board_ids)
      pending_replacements = [[starting_old_board, starting_new_board]]

      user_home_changed = relink_board_for(user, {:boards => boards, :copy_id => starting_new_board.global_id, :pending_replacements => pending_replacements, :update_preference => (update_inline ? 'update_inline' : nil), :make_public => make_public, :authorized_user => auth_user})
      
      # if the user's home board was replaced, update their preferences
      if user_home_changed
        new_home = user_home_changed
        user.update_setting({
          'preferences' => {'home_board' => {
            'id' => new_home.global_id,
            'key' => new_home.key
          }}
        })
      else
        home = Board.find_by_path(user.settings['preferences']['home_board']['id'])
        home.track_downstream_boards!
      end
      
    end

    def copy_board_links_for(user, opts)
      auth_user = opts[:authorized_user]
      starting_old_board = opts[:starting_old_board] || raise("starting_old_board required")
      starting_new_board = opts[:starting_new_board] || raise("starting_new_board required")
      make_public = opts[:make_public] || false
      board_ids = starting_old_board.settings['downstream_board_ids']
      if opts[:valid_ids]
        board_ids = board_ids & opts[:valid_ids]
      end
      boards = Board.find_all_by_path(board_ids)
      pending_replacements = [[starting_old_board, starting_new_board]]
      boards.each do |orig|
        if !orig.allows?(user, 'view') && !orig.allows?(auth_user, 'view')
          # TODO: make a note somewhere that a change should have happened but didn't due to permissions
        else
          copy = orig.copy_for(user, make_public, starting_new_board.global_id)
          pending_replacements << [orig, copy]
        end
      end
      boards = [starting_old_board] + boards

      relink_board_for(user, {:boards => boards, :copy_id => starting_new_board.global_id, :pending_replacements => pending_replacements, :update_preference => 'update_inline', :make_public => make_public, :authorized_user => auth_user})
      @replacement_map
    end
    
    def relink_board_for(user, opts)
      auth_user = opts[:authorized_user]
      boards = opts[:boards] || raise("boards required")
      pending_replacements = opts[:pending_replacements] || raise("pending_replacements required")
      update_preference = opts[:update_preference]
      # maintain mapping of old boards to their replacements
      replacement_map = {}
      pending_replacements.each do |old_board, new_board|
        replacement_map[old_board.global_id] = new_board
      end
      # for each board that needs replacing...
      while pending_replacements.length > 0
        old_board, new_board = pending_replacements.shift
        # iterate through all the original boards and look for references to the old board
        boards.each do |orig|
          board = replacement_map[orig.global_id] || orig
          # find all boards in the user's set that point to old_board_id
          if board.links_to?(old_board)
            if !board.allows?(user, 'view') && !board.allows?(auth_user, 'view')
              # TODO: make a note somewhere that a change should have happened but didn't due to permissions
            elsif update_preference == 'update_inline' && board.allows?(user, 'edit')
              # if you explicitly said update instead of replace my boards, then go ahead
              # and update in-place.
              board.replace_links!(old_board, new_board)
            elsif !board.just_for_user?(user)
              # if it's not already private for the user, make a private copy for the user 
              # and add to list of replacements to handle.
              copy = board.copy_for(user, opts[:make_public], opts[:copy_id])
              copy.replace_links!(old_board, new_board)
              replacement_map[board.global_id] = copy
              pending_replacements << [board, copy]
            else
              # if it's private for the user, and no one else is using it, go ahead and
              # update it in-place
              board.replace_links!(old_board, new_board)
            end
          else
          end
        end
      end
      @replacement_map = replacement_map
      
      return replacement_map[user.settings['preferences']['home_board']['id']] if user.settings['preferences'] && user.settings['preferences']['home_board']
    end
  end
end