# frozen_string_literal: true

module RedmineServerlessSes
  # A project's email settings go with the project: deleting the project
  # deletes its row in serverless_project_mail_settings, which would otherwise
  # keep reserving the project's alias.
  module ProjectPatch
    def self.install
      return if Project.reflect_on_association(:serverless_mail_setting)

      Project.has_one :serverless_mail_setting, class_name: 'ServerlessProjectMailSetting', dependent: :delete
    end
  end
end
