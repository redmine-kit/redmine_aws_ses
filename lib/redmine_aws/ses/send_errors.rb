# frozen_string_literal: true

module RedmineAws
  module SES
    # The three kinds of SES v2 SendEmail errors (Serverless docs/mail.md):
    #
    # - temporary: throttling, SES 5xx and network errors. Retried inside the
    #   job, up to ATTEMPTS runs.
    # - message: a problem with this message or its recipients. Dropped; a
    #   record is kept when Redmine AWS SQS is installed.
    # - account: a problem with the account or the settings, and any other
    #   error. Raised, so that the queue retries the job and keeps it in the
    #   dead-letter queue, where it is recorded.
    module SendErrors
      ATTEMPTS = 5
      TEMPORARY = %w[TooManyRequestsException InternalFailure ServiceUnavailable].freeze
      MESSAGE = %w[MessageRejected BadRequestException].freeze

      module_function

      def kind(error)
        if error.is_a?(Seahorse::Client::NetworkingError) || TEMPORARY.include?(code(error)) || server_error?(error)
          :temporary
        elsif MESSAGE.include?(code(error))
          :message
        else
          :account
        end
      end

      def code(error)
        error.respond_to?(:code) ? error.code.to_s : error.class.name.demodulize
      end

      def server_error?(error)
        error.respond_to?(:context) && error.context.respond_to?(:http_response) &&
          error.context.http_response.status_code.to_i >= 500
      end

      # Waits like ActiveJob's :polynomially_longer without jitter: 3, 18, 83
      # and 258 seconds after the 1st to 4th runs, within SQS's 15 minutes.
      def wait(executions)
        (executions**4) + 2
      end

      # Called from Mailer::DeliveryJob's handler (DeliveryJobPatch).
      def handle(job, error)
        case kind(error)
        when :temporary
          raise error if job.executions >= ATTEMPTS

          job.retry_job(wait: wait(job.executions), error: error)
        when :message
          drop(job, error)
        else
          raise error
        end
      end

      # The log names the job, the mailer method and the error code only: SES's
      # messages name the recipients ("... failed the check in region ...:
      # <address>").
      def drop(job, error)
        Rails.logger.error "[redmine_aws_ses] dropped email #{job.job_id} (#{job.arguments.first(2).join('#')}): " \
                           "#{code(error)}"
        return unless defined?(AwsSqsJobFailure)

        AwsSqsJobFailure.record!(ActiveSupport::JSON.dump(job.serialize), error, attempts: job.executions)
      end
    end
  end
end
