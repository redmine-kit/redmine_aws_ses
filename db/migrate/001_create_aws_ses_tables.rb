# frozen_string_literal: true

# The tables of the SES plugin: the received emails, each project's settings
# of receiving, and the snapshots of the account's state.
#
# One method per table; create_table and add_index in them are recorded as in
# change, so that the migration reverses.
class CreateAwsSesTables < ActiveRecord::Migration[8.1]
  def change
    create_received_mails
    create_project_mail_settings
    create_snapshots
  end

  private

  def create_received_mails # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- one table, one line per column
    create_table :aws_ses_received_mails do |t|
      t.string :message_id, null: false
      t.string :s3_key
      t.string :mail_from
      t.string :subject
      t.text :recipients
      # SES's mail.source, the envelope MAIL FROM, for registered forwarders.
      t.string :envelope_from
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

  def create_project_mail_settings # rubocop:disable Metrics/MethodLength -- one table, one line per column
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

  def create_snapshots
    create_table :aws_ses_snapshots do |t|
      t.datetime :fetched_at, null: false
      t.text :data
    end
    add_index :aws_ses_snapshots, :fetched_at
  end
end
