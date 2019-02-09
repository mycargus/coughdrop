class DropUniquenessForTags < ActiveRecord::Migration[5.0]
  def change
    remove_index :nfc_tags, [:tag_id, :public, :user_id]
    add_index :nfc_tags, [:tag_id, :public, :user_id]
  end
end
