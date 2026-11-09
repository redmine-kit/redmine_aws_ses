# frozen_string_literal: true

require 'aws-actionmailer-ses'
require 'aws-sdk-s3'

# The part of Redmine Serverless SES that must be in place before Rails
# finishes initializing: the SES delivery method (:ses_v2, registered by
# aws-actionmailer-ses) and the interceptor that sets per-project senders.
# Bundler loads this file (the plugin is also a gem); init.rb, which Redmine
# runs later, does the rest. It is outside lib/, which Redmine autoloads.
module RedmineServerlessSesBoot
  # Registered once; it calls the reloadable code in lib/.
  module Interceptor
    def self.delivering_email(message)
      RedmineServerlessSes::ProjectSender.call(message)
    end
  end

  if defined?(Rails::Railtie)
    class Railtie < Rails::Railtie
      config.after_initialize do
        ActionMailer::Base.register_interceptor(RedmineServerlessSesBoot::Interceptor)
      end
    end
  end
end
