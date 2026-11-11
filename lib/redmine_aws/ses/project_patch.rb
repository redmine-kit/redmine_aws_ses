# frozen_string_literal: true

module RedmineAws
  module SES
    # A project's email settings go with the project: deleting the project
    # deletes its row in aws_ses_project_mail_settings.
    module ProjectPatch
      def self.install
        return if Project.reflect_on_association(:aws_ses_mail_setting)

        Project.has_one :aws_ses_mail_setting, class_name: 'AwsSesProjectMailSetting', dependent: :delete
      end
    end
  end
end
