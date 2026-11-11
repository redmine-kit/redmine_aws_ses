# frozen_string_literal: true

module RedmineAws
  module SES
    # Adds the handling of SES errors to Redmine's mail job
    # (Mailer::DeliveryJob, Mailer.delivery_job). The errors reach the job only
    # where raise_delivery_errors is true: in the process that runs jobs.
    module DeliveryJobPatch
      def self.install
        job = Mailer.delivery_job
        return if job.include?(self)

        job.include(self)
        # Declared after ActionMailer's own StandardError handler, so it is
        # tried first.
        job.rescue_from(::Aws::SESV2::Errors::ServiceError, Seahorse::Client::NetworkingError) do |error|
          RedmineAws::SES::SendErrors.handle(self, error)
        end
      end
    end
  end
end
