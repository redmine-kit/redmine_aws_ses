# frozen_string_literal: true

# The part of Redmine AWS SES that must be in place before Rails finishes
# initializing: the SES delivery method (:ses_v2, registered by
# aws-actionmailer-ses) and the interceptor that sets per-project senders.
# Bundler loads this file (the plugin is also a gem); init.rb, which Redmine
# runs later, does the rest. It is outside lib/, which Redmine autoloads. It
# defines only RedmineAws::SES::Boot: the modules around it are empty here,
# and lib/redmine_aws.rb and lib/redmine_aws/ses.rb, which the code loader
# then skips, are loaded by the init.rb files. The module names of
# redmine_aws come first: with RedmineAws defined, the code loader names the
# files under lib/redmine_aws/ while it sets up.
require 'redmine_aws/inflections'
require 'aws-actionmailer-ses'
require 'aws-sdk-s3'

module RedmineAws
  module SES
    module Boot
      # Registered once; it calls the reloadable code in lib/.
      module Interceptor
        def self.delivering_email(message)
          RedmineAws::SES::ProjectSender.call(message)
        end
      end

      if defined?(Rails::Railtie)
        class Railtie < Rails::Railtie
          config.after_initialize do
            ActionMailer::Base.register_interceptor(RedmineAws::SES::Boot::Interceptor)
          end
        end
      end
    end
  end
end
