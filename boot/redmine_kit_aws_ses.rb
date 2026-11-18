# frozen_string_literal: true

# The part of Redmine Kit AWS SES that must be in place before Rails finishes
# initializing: the SES delivery method (:ses_v2, registered by
# aws-actionmailer-ses) and the interceptor that sets per-project senders.
# Bundler loads this file (the plugin is also a gem); init.rb, which Redmine
# runs later, does the rest. It is outside lib/, which Redmine autoloads. It
# defines only RedmineKit::Aws::Ses::Boot: the modules around it are empty
# and nested here (RedmineKit belongs to no plugin), and lib/redmine_kit/aws.rb
# and lib/redmine_kit/aws/ses.rb, which the code loader then skips, are
# loaded by the init.rb files.
require 'aws-actionmailer-ses'
require 'aws-sdk-s3'

module RedmineKit
  module Aws
    module Ses
      module Boot
        # Registered once; it calls the reloadable code in lib/.
        module Interceptor
          def self.delivering_email(message)
            RedmineKit::Aws::Ses::ProjectSender.call(message)
          end
        end

        if defined?(Rails::Railtie)
          class Railtie < Rails::Railtie
            config.after_initialize do
              ActionMailer::Base.register_interceptor(RedmineKit::Aws::Ses::Boot::Interceptor)
            end
          end
        end
      end
    end
  end
end
