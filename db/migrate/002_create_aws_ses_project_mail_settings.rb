# frozen_string_literal: true

class CreateAwsSesProjectMailSettings < ActiveRecord::Migration[8.1]
  def change # rubocop:disable Metrics/MethodLength -- one table, one line per column
    create_table :aws_ses_project_mail_settings do |t|
      t.references :project, null: false, index: { unique: true }, foreign_key: false
      t.boolean :receive, null: false, default: false
      t.integer :tracker_id
      t.integer :category_id
      t.integer :priority_id
      t.integer :assigned_to_id
      t.boolean :is_private, null: false, default: false
      t.string :unknown_user, null: false, default: 'ignore'
      # Forwarded email (docs/receiving.md#forwarded-email).
      t.text :forwarders
      t.boolean :import_forwarded, null: false, default: false
      t.string :forwarded_author, null: false, default: 'external'
      t.timestamps
    end
  end
end
