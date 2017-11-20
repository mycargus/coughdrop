class AddSecondaryUserIdToUserLinks < ActiveRecord::Migration[5.0]
  def change
    add_column :user_links, :secondary_user_id, :integer
    add_index :user_links, [:secondary_user_id]
  end
end
