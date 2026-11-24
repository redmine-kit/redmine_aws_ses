# frozen_string_literal: true

module RedmineKit
  module Aws
    module Ses
      # The "Email" tab of project settings, when addresses per project are on.
      # Prepended to ProjectsHelper: it changes ProjectsHelper#project_settings_tabs,
      # which lists the tabs, because Redmine has no hook for them. The tab is
      # added after Redmine's own filter, so the permission is checked here.
      module ProjectSettingsTab
        def self.install
          ProjectsHelper.prepend(self) unless ProjectsHelper.include?(self)
        end

        # Whether the project has the tab: while addresses per project are on.
        # The one rule for Redmine's tab and the new UI's (the manifest's
        # `enabled`).
        def self.enabled?(_project)
          RedmineKit::Aws::Ses.per_project_addresses?
        end

        def project_settings_tabs
          tabs = super
          if ProjectSettingsTab.enabled?(@project) &&
             User.current.allowed_to?(:manage_aws_ses_mail_settings, @project)
            tabs << { name: 'aws_ses_mail', action: :manage_aws_ses_mail_settings,
                      partial: 'aws_ses_project_mail_settings/form', label: :label_aws_ses_project_mail }
          end
          tabs
        end
      end
    end
  end
end
