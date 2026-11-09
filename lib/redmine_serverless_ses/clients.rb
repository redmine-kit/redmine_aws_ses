# frozen_string_literal: true

module RedmineServerlessSes
  # The AWS clients of the plugin. SES uses the settings of the delivery
  # method (ses_v2_settings in configuration.yml) when they are set; tests
  # replace the clients with ones that have SDK response stubs.
  module Clients
    class << self
      attr_writer :ses, :s3

      def ses
        @ses ||= Aws::SESV2::Client.new(ses_settings)
      end

      def s3
        @s3 ||= Aws::S3::Client.new
      end

      def reset
        @ses = @s3 = nil
      end

      private

      def ses_settings
        settings = ActionMailer::Base.respond_to?(:ses_v2_settings) ? ActionMailer::Base.ses_v2_settings.to_h : {}
        settings.slice(:region, :credentials, :endpoint)
      end
    end
  end
end
