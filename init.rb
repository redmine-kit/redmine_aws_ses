# frozen_string_literal: true

# Redmine runs this when it prepares the code. The SES delivery method and the
# interceptor for per-project senders are in boot/redmine_aws_ses.rb, which
# Bundler loads earlier.

# Redmine's code loader (Zeitwerk) skips lib/redmine_aws/ses.rb when
# RedmineAws::SES is already defined, as it is when Bundler has loaded
# boot/redmine_aws_ses.rb. The file is then loaded here.
require File.expand_path('lib/redmine_aws/ses', __dir__) unless defined?(RedmineAws::SES::VERSION)

Redmine::Plugin.register :redmine_aws_ses do
  # First, so that Redmine names a missing redmine_aws before anything uses it.
  requires_redmine_plugin :redmine_aws, version_or_higher: '0.1.0'
  name 'Redmine AWS SES'
  author 'Redmine Kit'
  description "Sends and receives Redmine's email with Amazon SES"
  version RedmineAws::SES::VERSION
  url 'https://github.com/redmine-kit/redmine_aws_ses'
  author_url 'https://github.com/redmine-kit'
  requires_redmine version_or_higher: '7.0.0'

  # Stored in Setting.plugin_redmine_aws_ses and changed on the
  # "Receiving email" tab; no partial, so the plugin list has no Configure
  # link.
  settings default: RedmineAws::SES::DEFAULTS.dup

  # projects: :settings opens project settings, as Redmine's own permissions
  # for a settings tab do (manage_categories and others).
  permission :manage_aws_ses_mail_settings, { projects: :settings, aws_ses_project_mail_settings: [:update] },
             require: :member
end

RedmineAws::SES.setup
