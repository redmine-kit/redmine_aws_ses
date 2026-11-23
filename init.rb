# frozen_string_literal: true

# The plugins this one requires (config/dependencies.yml): without one,
# Redmine stops here and names it.
load File.expand_path('config/dependencies.rb', __dir__)

# Redmine runs this when it prepares the code. The SES delivery method and the
# interceptor for per-project senders are in boot/redmine_kit_aws_ses.rb, which
# Bundler loads earlier.

# Redmine's code loader (Zeitwerk) skips lib/redmine_kit/aws/ses.rb when
# RedmineKit::Aws::Ses is already defined, as it is when Bundler has loaded
# boot/redmine_kit_aws_ses.rb. The file is then loaded here.
require File.expand_path('lib/redmine_kit/aws/ses', __dir__) unless defined?(RedmineKit::Aws::Ses::VERSION)

Redmine::Plugin.register :redmine_kit_aws_ses do
  name 'Redmine Kit AWS SES'
  author 'Redmine Kit'
  description "Sends and receives Redmine's email with Amazon SES"
  version RedmineKit::Aws::Ses::VERSION
  url 'https://github.com/redmine-kit/redmine_aws_ses'
  author_url 'https://github.com/redmine-kit'
  requires_redmine version_or_higher: '7.0.0'

  # Stored in Setting.plugin_redmine_kit_aws_ses and changed on the
  # "Receiving email" tab; no partial, so the plugin list has no Configure
  # link.
  settings default: RedmineKit::Aws::Ses::DEFAULTS.dup

  # projects: :settings opens project settings, as Redmine's own permissions
  # for a settings tab do (manage_categories and others).
  permission :manage_aws_ses_mail_settings, { projects: :settings, aws_ses_project_mail_settings: [:update] },
             require: :member
end

RedmineKit::Aws::Ses.setup
