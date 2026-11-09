# frozen_string_literal: true

# Redmine runs this when it prepares the code. The SES delivery method and the
# interceptor for per-project senders are in boot/redmine_serverless_ses.rb,
# which Bundler loads earlier.
Redmine::Plugin.register :redmine_serverless_ses do
  name 'Redmine Serverless SES'
  author 'Redmine Kit'
  description "Sends and receives Redmine's email with Amazon SES"
  version RedmineServerlessSes::VERSION
  url 'https://github.com/redmine-kit/redmine_serverless_ses'
  author_url 'https://github.com/redmine-kit'
  requires_redmine version_or_higher: '7.0.0'

  # Stored in Setting.plugin_redmine_serverless_ses and changed on the
  # "Receiving email" tab; no partial, so the plugin list has no Configure
  # link.
  settings default: RedmineServerlessSes::DEFAULTS.dup

  permission :manage_serverless_mail_settings, { serverless_project_mail_settings: [:update] }, require: :member
end

RedmineServerlessSes.setup
