# frozen_string_literal: true

module RedmineAws
  module SES
    # The "Email" tab of project settings, when addresses per project are on.
    module ProjectSettingsTab
      def self.install
        ProjectsHelper.prepend(self) unless ProjectsHelper.include?(self)
      end

      def project_settings_tabs
        tabs = super
        if RedmineAws::SES.per_project_addresses? &&
           User.current.allowed_to?(:manage_aws_ses_mail_settings, @project)
          tabs << { name: 'aws_ses_mail', action: :manage_aws_ses_mail_settings,
                    partial: 'aws_ses_project_mail_settings/form', label: :label_aws_ses_project_mail }
        end
        tabs
      end
    end
  end
end
