class CreateNfcTags < ActiveRecord::Migration[5.0]
  def change
    create_table :nfc_tags do |t|
      t.string :tag_id
      t.string :user_id
      t.string :nonce
      t.boolean :public
      t.text :data
      t.timestamps
    end
    add_index :nfc_tags, [:tag_id, :public, :user_id], :unique => true
  end
end
