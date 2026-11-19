# frozen_string_literal: true

# The tasks' work is in RedmineKit::Aws::Ses::Tasks.
namespace :redmine_kit do
  namespace :aws do
    namespace :ses do
      desc 'Imports one message that SES stored in the mail bucket (MESSAGE_ID, SES_RECIPIENTS, SES_MAIL_FROM, ' \
           'SES_*_VERDICT)'
      task receive_mail: :environment do
        line, ok = RedmineKit::Aws::Ses::Tasks.receive_mail(ENV)
        ok ? puts(line) : abort(line)
      end

      desc 'Reads the state of SES and DNS for the email tabs of the AWS administration page (on a schedule)'
      task refresh: :environment do
        line, ok = RedmineKit::Aws::Ses::Tasks.refresh
        ok ? puts(line) : abort(line)
      end

      desc 'Deletes the records of received email older than a number of days. ' \
           'Use DAYS to set the number of days (default 90).'
      task prune: :environment do
        line, ok = RedmineKit::Aws::Ses::Tasks.prune(ENV)
        ok ? puts(line) : abort(line)
      end
    end
  end
end
