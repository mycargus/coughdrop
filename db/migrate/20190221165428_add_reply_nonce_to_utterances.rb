class AddReplyNonceToUtterances < ActiveRecord::Migration[5.0]
  def change
    add_column :utterances, :reply_nonce, :string
    add_index :utterances, [:reply_nonce], :unique => true
  end
end
