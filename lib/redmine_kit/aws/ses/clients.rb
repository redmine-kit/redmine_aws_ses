# frozen_string_literal: true

module RedmineKit
  module Aws
    module Ses
      # The AWS clients of the plugin, with the settings that redmine_kit_aws
      # shares (RedmineKit::Aws.client). SES uses the settings of the delivery
      # method (ses_v2_settings in configuration.yml) when they are set; tests
      # replace the clients with ones that have SDK response stubs.
      module Clients
        class << self
          attr_writer :ses, :s3

          def ses
            @ses ||= RedmineKit::Aws.client(::Aws::SESV2::Client, **ses_settings)
          end

          def s3
            @s3 ||= RedmineKit::Aws.client(::Aws::S3::Client)
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
  end
end
