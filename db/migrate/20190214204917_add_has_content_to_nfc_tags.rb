class AddHasContentToNfcTags < ActiveRecord::Migration[5.0]
  def change
    add_column :nfc_tags, :has_content, :boolean
    add_index :nfc_tags, [:tag_id, :has_content, :public, :user_id]
  end
end
