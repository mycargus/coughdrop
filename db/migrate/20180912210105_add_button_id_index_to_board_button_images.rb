class AddButtonIdIndexToBoardButtonImages < ActiveRecord::Migration[5.0]
  def change
    add_index :board_button_images, [:button_image_id]
  end
end
