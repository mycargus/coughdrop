class AddUniqueKeyToUserIntegrations < ActiveRecord::Migration[5.0]
  def change
    add_column :user_integrations, :unique_key, :string
    add_index :user_integrations, [:unique_key], :unique => true
  end
end
