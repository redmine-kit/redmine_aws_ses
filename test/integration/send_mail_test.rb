# frozen_string_literal: true

require_relative '../test_helper'
require 'net/http'

module RedmineServerlessSes
  # Sending through aws-actionmailer-ses (:ses_v2) to SES v2 (LocalStack or
  # moto, TEST_SES_BACKEND), and the connection check.
  class SendMailTest < ActiveSupport::TestCase
    include RedmineServerlessSes::TestHelper

    def setup
      @endpoint = ENV.fetch('AWS_ENDPOINT_URL_SESV2') { ENV.fetch('AWS_ENDPOINT_URL') }
      @ses_v1 = Aws::SES::Client.new(endpoint: @endpoint)
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

    def test_a_rejected_message_raises_in_the_worker
      saved = ActionMailer::Base.raise_delivery_errors
      ActionMailer::Base.raise_delivery_errors = true
      with_settings(mail_from: 'redmine@unverified.example') do
        assert_raises(Aws::SESV2::Errors::ServiceError) { Mailer.test_email(User.find(1)).deliver_now }
      end
    ensure
      ActionMailer::Base.raise_delivery_errors = saved
    end

    # moto has no SES v2 GetAccount (it answers NotFound); the check is also
    # covered by SDK response stubs (ServerlessMailSendingControllerTest).
    def test_the_connection_check
      skip 'moto has no SES v2 GetAccount' unless ses_backend == 'localstack'

      RedmineServerlessSes::Clients.ses = Aws::SESV2::Client.new(endpoint: @endpoint)
      result = RedmineServerlessAdmin.run_checks.find { |r| r.name == 'ses' }

      assert result.ok, result.detail
    end
  end
end
