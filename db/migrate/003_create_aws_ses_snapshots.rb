# frozen_string_literal: true

class CreateAwsSesSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :aws_ses_snapshots do |t|
      t.datetime :fetched_at, null: false
      t.text :data
    end
    add_index :aws_ses_snapshots, :fetched_at
  end
end
