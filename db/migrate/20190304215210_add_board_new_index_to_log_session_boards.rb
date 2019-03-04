class AddBoardNewIndexToLogSessionBoards < ActiveRecord::Migration[5.0]
  def change
    add_index :log_session_boards, [:board_id, :log_session_id]
  end
end
