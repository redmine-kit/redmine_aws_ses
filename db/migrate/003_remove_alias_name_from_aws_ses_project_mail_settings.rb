# frozen_string_literal: true

# A project's address is its identifier only (docs/admin.md#project-email-settings).
class RemoveAliasNameFromAwsSesProjectMailSettings < ActiveRecord::Migration[7.2]
  def change
    remove_index :aws_ses_project_mail_settings, :alias_name, unique: true
    remove_column :aws_ses_project_mail_settings, :alias_name, :string
  end
end
