class DeletedBoard < ActiveRecord::Base
  include SecureSerialize
  include GlobalId
  secure_serialize :settings
  before_save :generate_defaults
  belongs_to :user
  belongs_to :board
  replicated_model  
  
  def generate_defaults
    self.cleared ||= false
    true
  end
  
  def board_global_id
    related_global_id(self.board_id)
  end
  
  def restore!
    version = PaperTrail::Version.where(item_type: 'Board', item_id: self.board_id).order('created_at DESC')[0]
    if version
      board = Board.load_version(version)
      board.load_secure_object unless board.settings
      board.instance_variable_set('@buttons_changed', true)
      board.save!
    else
      raise "no valid version found"
    end
  end
  
  def self.find_by_path(path)
    if path && path.match(/\//)
      DeletedBoard.where(:key => path).order('id DESC').first
    else
      hash = id_pieces(path)
      DeletedBoard.find_by(:board_id => hash[:id])
    end
  end
  
  def self.process(board)
    db = DeletedBoard.new
    db.key = board.key
    db.board_id = board.id
    db.user_id = board.user_id
    db.settings = {
      :stats => board.settings['stats']
    }
    db.save
    db
  end
  
  def self.flush_old_records
    count = 0
    DeletedBoard.where(['cleared = ? AND created_at < ?', false, 60.days.ago]).each do |db|
      # TODO: Flusher assumes the board object still exists, which is a bad assumption here
      Flusher.flush_board_by_db_id(db.board_id, db.key)
      db.cleared = true
      db.save
      count += 1
    end
    count
  end
end
