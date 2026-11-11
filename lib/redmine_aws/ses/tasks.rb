# frozen_string_literal: true

module RedmineAws
  module SES
    # The work of the rake tasks (lib/tasks/redmine_aws_ses.rake); each
    # returns the line the task prints.
    module Tasks
      module_function

      # MESSAGE_ID, and from the SES event SES_RECIPIENTS (receipt.recipients,
      # comma-separated), SES_MAIL_FROM (mail.source, the envelope sender) and
      # the verdicts (SES_SPAM_VERDICT, ...; Verdicts). A re-import gives
      # MESSAGE_ID only and uses what the first run recorded.
      def receive_mail(env)
        event = { recipients: env.fetch('SES_RECIPIENTS', '').split(','), verdicts: Verdicts.from_env(env),
                  envelope_from: env.fetch('SES_MAIL_FROM', nil) }
        record = Receiver.new(env.fetch('MESSAGE_ID', ''), event: event).run
        "#{record.message_id}: #{record.status}#{" (#{record.reason})" if record.reason}"
      end

      # The line and whether every section was read; the task fails
      # otherwise, so that the schedule's failures show (the log has the
      # errors).
      def refresh
        failed = AwsSesSnapshot.refresh!.data['errors'].to_h.keys
        return ['refreshed the SES state', true] if failed.empty?

        ["refreshed the SES state; failed: #{failed.join(', ')}", false]
      end

      def prune_records(days)
        days = days.presence || AwsSesReceivedMail::KEEP_DAYS
        "deleted #{AwsSesReceivedMail.prune(days)} record(s) older than #{days} days"
      end
    end
  end
end
