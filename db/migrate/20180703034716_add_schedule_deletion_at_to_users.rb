class AddScheduleDeletionAtToUsers < ActiveRecord::Migration[5.0]
  def change
    add_column :users, :schedule_deletion_at, :datetime
    add_index :users, [:schedule_deletion_at]
  end
end
