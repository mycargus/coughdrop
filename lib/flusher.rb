module Flusher
  def self.find_user(user_id, user_name)
    user = User.find_by_global_id(user_id)
    raise "user not found" unless user
    raise "wrong user!" unless user.user_name == user_name
    user
  end
  
  def self.flush_user_logs(user_id, user_name)
    user = find_user(user_id, user_name)
    # remove all logs tied to the user
    # don't remove anonymized user data from aggregate reports
    # make sure to remove from paper_trail as well
    sessions = LogSession.where(:user_id => user.id)
    sessions.each do |session|
      flush_record(session)
    end
    
    locations = ClusterLocation.where(:user_id => user.id)
    locations.each do |location|
      flush_record(location)
    end
    
    summaries = WeeklyStatsSummary.where(user_id: user.id)
    summaries.each do |summary|
      flush_record(summary)
    end
  end
  
  def self.flush_record(record, record_db_id=nil, record_class=nil)
    if record
      record.destroy 
      record_db_id = record.id
      record_class = record.class.to_s
    end
    flush_versions(record_db_id, record_class)
  end
  
  def self.flush_versions(record_db_id, record_class)
      PaperTrail::Version.where(:item_type => record_class, :item_id => record_db_id).delete_all
  end
  
  def self.flush_leftovers
    # 1. look for removable button_images and button_sounds and .destroy them if
    #    they are at least a week old and there are no board connections for them
    # 2. look for any board_button_images and board_button_sounds with no linked
    #    board, button or sound and .destroy them (also note it somewhere, in case
    #    there is a consistent leakage problem)
    # 3. look for any expired developer keys and .destroy them
    # 4. look for any log_session_boards that don't have a session or board
    #    and .destroy them (also note in case consistent leakage)
    # 5. look for any progress records more than a month old and destroy them
    # 6. look for any user_board_connections with no linked board or user
    #    and .destroy them (also note in case consistent leakage)
    # 7. look for any paper trail versions that point to records that
    #    don't exist anymore and .destroy them (also note in case consistent leakage)
    # TODO: also prune old versions? The list will get huge soon...
  end
  
  def self.flush_board(board_id, key, aggressive_flush=false)
    board = Board.find_by_global_id(board_id)
    raise "wrong board!" if !board || board.key != key
    flush_board_by_db_id(board.id, key, aggressive_flush)
  end
  
  def self.flush_board_by_db_id(board_db_id, key, aggressive_flush=false)
    # NOTE: the aggressive version of this method rips out anything used by the board, 
    # regardless of whether it is also used other places. For example, if I create a 
    # board and clone it and then aggressive-flush the cloned board, any images 
    # created on the original board will disappear.
    board = Board.find_by(:id => board_db_id)
    raise "wrong board!" if board && board.key != key
    # remove any button_image records
    # remove any board_button_images
    BoardButtonImage.where(:board_id => board_db_id).each do |bbi|
      full_flush = aggressive_flush
      bi = bbi.button_image
      if !full_flush && bi && bi.board_button_images.count <= 1
        full_flush = true
      end
      
      if bi && full_flush
        # TODO: reach into affected boards and remove the dead links
        BoardButtonImage.where(:button_image_id => bi.id).delete_all
        flush_record(bi)
      else
        BoardButtonImage.where(:id => bbi.id).delete_all
      end
    end
    # remove any button_sound records
    # remove any board_button_sounds
    BoardButtonSound.where(:board_id => board_db_id).each do |bbs|
      full_flush = aggressive_flush
      bs = bbs.button_sound
      if !full_flush && bs && bs.board_button_sounds.count <= 1
        full_flush = true
      end
      
      if bs && full_flush
        # TODO: reach into affected boards and remove the dead links
        BoardButtonSound.where(:button_sound_id => bs.id).delete_all
        flush_record(bs)
      else
        BoardButtonSound.where(:id => bbs.id).delete_all
      end
    end
    BoardDownstreamButtonSet.where(:board_id => board_db_id).each do |bs|
      flush_record(bs)
    end
    # remove any user_board_connections
    # remove as the home_board setting for any users
    # NOTE: this is aggressive, but probably necessary
    # TODO: build a notification for users who just lost their home board this way
    UserBoardConnection.where(:board_id => board_db_id).each do |bc|
      if bc.home
        user = bc.user
        user.settings['preferences']['home_board'] = nil
        user.save
      end
      flush_record(bc)
    end
    LogSessionBoard.where(:board_id => board_db_id).each do |sb|
      flush_record(sb)
    end
    flush_record(board, board_db_id, 'Board')
    # make sure to remove from paper_trail as well
  end
  
  def self.flush_user_boards(user_id, user_name)
    user = find_user(user_id, user_name)
    # remove all boards created by the user
    # make sure to remove from paper_trail as well
    boards = Board.where(:user_id => user.id)
    boards.each do |board|
      # if the board has no parent board, it is an original and can be aggressively
      # flushed (i.e. any clones of the board that still use images from this board
      # will lose those images). This is an extreme measure, obviously.
      aggressive_flush = !board.parent_board_id
      flush_board(board.global_id, board.key, aggressive_flush)
    end
  end
  
  def self.flush_user_completely(user_id, user_name)
    user = find_user(user_id, user_name)
    flush_user_logs(user_id, user_name)
    flush_user_boards(user_id, user_name)
    # remove the user's devices and utterances
    Device.where(:user_id => user.id).each do |device|
      flush_record(device)
    end
    Utterance.where(:user_id => user.id).each do |utterance|
      flush_record(utterance)
    end
    # TODO: remove any public comments by the user
    LogSession.where(:author_id => user.id).each do |note|
      note.author_id = 0
      note.save
    end
    flush_record(user, user.id, 'User')
  end
end