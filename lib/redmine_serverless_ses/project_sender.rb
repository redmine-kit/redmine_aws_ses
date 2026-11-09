# frozen_string_literal: true

module RedmineServerlessSes
  # Sends project notifications from the project's address
  # (docs/admin.md#project-email-settings). Redmine marks them with the
  # X-Redmine-Project header; other email keeps the emission address. Used
  # when "per-project senders" and "addresses per project" are on.
  module ProjectSender
    module_function

    def call(message)
      return unless RedmineServerlessSes.per_project_addresses? && RedmineServerlessSes.project_senders?

      project = project_of(message)
      return unless project

      setting = ServerlessProjectMailSetting.find_by(project_id: project.id)
      address = ServerlessProjectMailSetting.address_for(project)
      return unless address

      message.from = with_display_name(message, address)
      # Replies to a project that does not receive email go to the emission
      # address.
      message.reply_to = Setting.mail_from unless setting&.receive?
    end

    def project_of(message)
      identifier = message.header['X-Redmine-Project']&.value
      identifier && Project.find_by(identifier: identifier)
    end

    def with_display_name(message, address)
      name = message[:from]&.display_names&.first
      name.present? ? %("#{name.delete('"')}" <#{address}>) : address
    end
  end
end
