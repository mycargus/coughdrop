class CreateJobStashes < ActiveRecord::Migration[5.0]
  def change
    create_table :job_stashes do |t|
      t.text :data

      t.timestamps
    end
    add_index :job_stashes, [:created_at]
  end
end
