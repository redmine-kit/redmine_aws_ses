# frozen_string_literal: true

module RedmineKit
  module Aws
    module Ses
      # Chooses the project of a received message from its recipients
      # (Serverless docs/mail.md#importing). The recipients are the envelope
      # recipients (SES's receipt.recipients), so Bcc works; a Project: keyword in
      # the body cannot change the choice.
      class Routing
        Target = Struct.new(:project, :setting, keyword_init: true)

        def initialize(settings: RedmineKit::Aws::Ses.settings, domain: RedmineKit::Aws::Ses.domain)
          @settings = settings
          @domain = domain
          @globals = RedmineKit::Aws::Ses.global_local_parts
        end

        # The first recipient on Redmine's domain that names a project that
        # receives email; nil when none does (the message is dropped).
        def target(recipients)
          local_parts(recipients).each do |local|
            target = target_for(local)
            return target if target
          end
          nil
        end

        private

        def local_parts(recipients)
          Array(recipients).filter_map do |address|
            local, domain = address.to_s.strip.downcase.split('@', 2)
            local if domain && domain == @domain && local.present?
          end
        end

        def target_for(local)
          base, sub = local.split('+', 2)
          if @globals.include?(base)
            global_target(sub)
          elsif RedmineKit::Aws::Ses.per_project_addresses?
            setting = AwsSesProjectMailSetting.receiving_for(base)
            setting && Target.new(project: setting.project, setting: setting)
          end
        end

        # The address for the whole Redmine: with Redmine's subaddress
        # (redmine+<identifier>@) when addresses per project are off, otherwise
        # the default project or nothing.
        def global_target(sub)
          if sub.present? && !RedmineKit::Aws::Ses.per_project_addresses?
            project = Project.active.find_by(identifier: sub)
            return project && Target.new(project: project)
          end
          return unless @settings['global_mail'] == 'default_project'

          project = Project.active.find_by(identifier: @settings['default_project'])
          project && Target.new(project: project, setting: AwsSesProjectMailSetting.find_by(project: project))
        end
      end
    end
  end
end
