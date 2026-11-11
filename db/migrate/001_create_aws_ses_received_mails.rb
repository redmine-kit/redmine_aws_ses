# frozen_string_literal: true

class CreateAwsSesReceivedMails < ActiveRecord::Migration[8.1]
  def change
    create_table :aws_ses_received_mails do |t|
      t.string :message_id, null: false
      t.string :s3_key
      t.string :mail_from
      t.string :subject
      t.text :recipients
      t.string :spam_verdict
      t.string :virus_verdict
      t.string :dmarc_verdict
      t.string :dmarc_policy
      t.string :spf_verdict
      t.string :dkim_verdict
      t.references :project, foreign_key: false
      t.string :status, null: false
      t.string :reason
      t.string :target_type
      t.integer :target_id
      t.datetime :received_at
      t.datetime :processed_at
      t.timestamps
    end
    add_index :aws_ses_received_mails, :message_id, unique: true
    add_index :aws_ses_received_mails, :created_at
  end
end
