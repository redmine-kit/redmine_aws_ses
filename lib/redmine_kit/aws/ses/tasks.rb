# frozen_string_literal: true

module RedmineKit
  module Aws
    module Ses
      # The work of the rake tasks (lib/tasks/redmine_kit_aws_ses.rake); each
      # returns the line the task prints.
      module Tasks
        # Five digits at most (about 270 years), which keeps the cut-off date
        # well within the database's range.
        MAX_DAYS = 99_999
        DAYS = /\A[1-9][0-9]{0,4}\z/

        module_function

        # MESSAGE_ID, and from the SES event SES_RECIPIENTS (receipt.recipients,
        # comma-separated), SES_MAIL_FROM (mail.source, the envelope sender) and
        # the verdicts (SES_SPAM_VERDICT, ...; Verdicts). A re-import gives
        # MESSAGE_ID only and uses what the first run recorded. The line and
        # whether MESSAGE_ID was valid: a missing or malformed one imports
        # nothing, and the task aborts with the line.
        def receive_mail(env)
          id = env.fetch('MESSAGE_ID', '')
          unless Receiver::MESSAGE_ID.match?(id)
            return ["Invalid MESSAGE_ID #{id} given. The value must be the ID of a message in the mail bucket.", false]
          end

          event = { recipients: env.fetch('SES_RECIPIENTS', '').split(','), verdicts: Verdicts.from_env(env),
                    envelope_from: env.fetch('SES_MAIL_FROM', nil) }
          record = Receiver.new(id, event: event).run
          ["#{record.message_id}: #{record.status}#{" (#{record.reason})" if record.reason}", true]
        end

        # The line and whether every section was read; the task fails
        # otherwise, so that the schedule's failures show (the log has the
        # errors).
        def refresh
          failed = AwsSesSnapshot.refresh!.data['errors'].to_h.keys
          return ['refreshed the SES state', true] if failed.empty?

          ["refreshed the SES state; failed: #{failed.join(', ')}", false]
        end

        # DAYS, default AwsSesReceivedMail::KEEP_DAYS. The line and whether
        # DAYS was valid: a value that isn't a whole number of days from 1 to
        # MAX_DAYS deletes nothing, and the task aborts with the line, as
        # Redmine's redmine:users:prune does.
        def prune(env)
          days = prune_days(env['DAYS'])
          unless days
            return ["Invalid DAYS #{env['DAYS']} given. The value must be an integer from 1 to #{MAX_DAYS}.", false]
          end

          ["deleted #{AwsSesReceivedMail.prune(days)} record(s) older than #{days} days", true]
        end

        def prune_days(value)
          return AwsSesReceivedMail::KEEP_DAYS if value.nil?

          value.to_i if DAYS.match?(value)
        end
      end
    end
  end
end
