class CreateUserLinks < ActiveRecord::Migration[5.0]
  def change
    create_table :user_links do |t|
      t.integer :user_id
      t.string :record_code
      t.text :data
      t.timestamps
    end
    add_index :user_links, [:user_id]
    add_index :user_links, [:record_code]
  end
end
