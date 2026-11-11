# frozen_string_literal: true

class CreateAwsSesProjectMailSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :aws_ses_project_mail_settings do |t|
      t.references :project, null: false, index: { unique: true }, foreign_key: false
      t.boolean :receive, null: false, default: false
      t.string :alias_name
      t.integer :tracker_id
      t.integer :category_id
      t.integer :priority_id
      t.integer :assigned_to_id
      t.boolean :is_private, null: false, default: false
      t.string :unknown_user, null: false, default: 'ignore'
      t.timestamps
    end
    add_index :aws_ses_project_mail_settings, :alias_name, unique: true
  end
end
