class CreateLogMergers < ActiveRecord::Migration[5.0]
  def change
    create_table :log_mergers do |t|
      t.datetime :merge_at
      t.boolean :started
      t.integer :log_session_id
      t.timestamps
    end
    add_index :log_mergers, [:log_session_id]
  end
end
