# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # Redmine's mail job with the SES delivery method on SDK response stubs,
    # each SendEmail error raised one by one.
    class SendErrorsTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper
      include ActiveJob::TestHelper

      def setup
        @saved_adapter = ActiveJob::Base.queue_adapter
        ActiveJob::Base.queue_adapter = :test
        @saved = [ActionMailer::Base.delivery_method, ActionMailer::Base.raise_delivery_errors,
                  ActionMailer::Base.ses_v2_settings]
        ActionMailer::Base.delivery_method = :ses_v2
        ActionMailer::Base.raise_delivery_errors = true
      end

      def teardown
        ActiveJob::Base.queue_adapter = @saved_adapter
        ActionMailer::Base.delivery_method, ActionMailer::Base.raise_delivery_errors,
          ActionMailer::Base.ses_v2_settings = @saved
      end

      def deliver(error, executions: 0)
        client = ::Aws::SESV2::Client.new(stub_responses: { send_email: error || { message_id: 'm1' } })
        ActionMailer::Base.ses_v2_settings = { sesv2_client: client }
        job = Mailer.delivery_job.new('Mailer', 'test_email', 'deliver_now', args: [User.find(1)])
        job.executions = executions
        job.perform_now
        client
      end

      def test_email_is_sent_through_ses_v2
        client = deliver(nil)
        request = client.api_requests.find { |r| r[:operation_name] == :send_email }

        assert_match(/Subject: /, request[:params][:content][:raw][:data])
      end

      def test_temporary_errors_are_retried_in_the_job
        %w[TooManyRequestsException InternalFailure].each do |error|
          clear_enqueued_jobs
          assert_nothing_raised { deliver(error) }
          assert_equal 1, enqueued_jobs.size, error
        end
      end

      def test_temporary_errors_are_raised_after_the_last_attempt
        assert_raises(::Aws::SESV2::Errors::TooManyRequestsException) do
          deliver('TooManyRequestsException', executions: SendErrors::ATTEMPTS - 1)
        end
      end

      def test_account_errors_are_raised_for_the_queue
        %w[SendingPausedException AccountSuspendedException MailFromDomainNotVerifiedException NotFoundException
           LimitExceededException AccessDeniedException].each do |error|
          clear_enqueued_jobs
          assert_raises(::Aws::SESV2::Errors::ServiceError, error) { deliver(error) }
          assert_empty enqueued_jobs, error
        end
      end

      def test_message_errors_are_dropped
        %w[MessageRejected BadRequestException].each do |error|
          clear_enqueued_jobs
          assert_nothing_raised { deliver(error) }
          assert_empty enqueued_jobs, error
        end
      end

      # SES's message names the recipient; the log keeps the code only.
      def test_the_log_of_a_dropped_email_has_no_address
        rejected = { status_code: 400, headers: { 'x-amzn-ErrorType' => 'MessageRejected' },
                     body: { message: 'Email address is not verified. The following identities failed the check ' \
                                      'in region US-EAST-1: jsmith@somenet.foo' }.to_json }
        io = StringIO.new
        saved = Rails.logger
        Rails.logger = Logger.new(io)
        deliver(rejected)

        assert_match(/dropped email \S+ \(Mailer#test_email\): MessageRejected$/, io.string)
        assert_not_includes io.string, 'somenet.foo'
      ensure
        Rails.logger = saved
      end

      def test_waits_fit_in_sqs_delay
        waits = (1...SendErrors::ATTEMPTS).map { |n| SendErrors.wait(n) }

        assert_equal [3, 18, 83, 258], waits
        assert_operator waits.max, :<=, 15.minutes
      end

      def test_kinds
        network = Seahorse::Client::NetworkingError.new(StandardError.new('reset'))

        assert_equal :temporary, SendErrors.kind(network)
      end
    end
  end
end
