class AddHiglightedToLogSessions < ActiveRecord::Migration[5.0]
  def change
    add_column :log_sessions, :highlighted, :boolean
    add_index :log_sessions, [:user_id, :highlighted]
  end
end
