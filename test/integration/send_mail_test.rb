# frozen_string_literal: true

require_relative '../test_helper'
require 'net/http'

module RedmineAws
  module SES
    # Sending through aws-actionmailer-ses (:ses_v2) to SES v2 (LocalStack or
    # moto, TEST_SES_BACKEND). The connection check (GetAccount) is in
    # AccountTest: neither emulator has GetAccount.
    class SendMailTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper

      def setup
        @endpoint = ENV.fetch('AWS_ENDPOINT_URL_SESV2') { ENV.fetch('AWS_ENDPOINT_URL') }
        @ses_v1 = ::Aws::SES::Client.new(endpoint: @endpoint)
        @ses_v1.verify_domain_identity(domain: DOMAIN)
        @saved = [ActionMailer::Base.delivery_method, ActionMailer::Base.ses_v2_settings,
                  ActionMailer::Base.perform_deliveries]
        ActionMailer::Base.delivery_method = :ses_v2
        ActionMailer::Base.ses_v2_settings = { endpoint: @endpoint }
        ActionMailer::Base.perform_deliveries = true
      end

      def teardown
        ActionMailer::Base.delivery_method, ActionMailer::Base.ses_v2_settings,
          ActionMailer::Base.perform_deliveries = @saved
      end

      def ses_backend
        ENV.fetch('TEST_SES_BACKEND') { ENV.fetch('TEST_AWS_BACKEND', nil) }
      end

      # Messages the backend accepted: LocalStack lists them at /_aws/ses;
      # moto counts them in the send quota.
      def sent_count
        if ses_backend == 'localstack'
          JSON.parse(Net::HTTP.get(URI("#{@endpoint}/_aws/ses")))['messages'].size
        else
          @ses_v1.get_send_quota.sent_last_24_hours.to_i
        end
      end

      def test_a_notification_is_sent_through_ses_v2
        with_ses_settings do
          before = sent_count
          Mailer.test_email(User.find(1)).deliver_now

          assert_operator sent_count, :>, before
        end
      end

      # Real SES rejects a sender that is not a verified identity with
      # MessageRejected. LocalStack does not check identities, so that answer is
      # an SDK response stub, on every backend; the worker must raise it.
      REJECTED = 'Email address is not verified. The following identities failed the check in region ' \
                 'US-EAST-1: redmine@unverified.example'

      def test_a_rejected_message_raises_in_the_worker
        with_rejecting_ses do
          error = assert_raises(::Aws::SESV2::Errors::MessageRejected) { Mailer.test_email(User.find(1)).deliver_now }

          assert_equal REJECTED, error.message
        end
      end

      private

      # The delivery method with a client that rejects the sender, and
      # delivery errors raised, as in the worker.
      def with_rejecting_ses(&)
        saved = [ActionMailer::Base.raise_delivery_errors, ActionMailer::Base.ses_v2_settings]
        client = ::Aws::SESV2::Client.new(stub_responses: true)
        client.stub_responses(:send_email, ::Aws::SESV2::Errors::MessageRejected.new(nil, REJECTED))
        ActionMailer::Base.raise_delivery_errors = true
        ActionMailer::Base.ses_v2_settings = { sesv2_client: client }
        with_settings(mail_from: 'redmine@unverified.example', &)
      ensure
        ActionMailer::Base.raise_delivery_errors, ActionMailer::Base.ses_v2_settings = saved
      end
    end
  end
end
