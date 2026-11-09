# frozen_string_literal: true

module RedmineServerlessSes
  # The "Email" tab of project settings, when addresses per project are on.
  module ProjectSettingsTab
    def self.install
      ProjectsHelper.prepend(self) unless ProjectsHelper.include?(self)
    end

    def project_settings_tabs
      tabs = super
      if RedmineServerlessSes.per_project_addresses? &&
         User.current.allowed_to?(:manage_serverless_mail_settings, @project)
        tabs << { name: 'serverless_mail', action: :manage_serverless_mail_settings,
                  partial: 'serverless_project_mail_settings/form', label: :label_serverless_project_mail }
      end
      tabs
    end
  end
end
