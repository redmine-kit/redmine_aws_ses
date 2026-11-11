# frozen_string_literal: true

namespace :redmine_aws_ses do
  # MESSAGE_ID, and from the SES event SES_RECIPIENTS (comma-separated) and
  # the verdicts (SES_SPAM_VERDICT, ...; RedmineAws::SES::Verdicts). A
  # re-import gives MESSAGE_ID only and uses what the first run recorded.
  desc 'Imports one message that SES stored in the mail bucket (MESSAGE_ID, SES_RECIPIENTS, SES_*_VERDICT)'
  task receive_mail: :environment do
    recipients = ENV.fetch('SES_RECIPIENTS', '').split(',')
    verdicts = RedmineAws::SES::Verdicts.from_env
    record = RedmineAws::SES::Receiver.new(ENV.fetch('MESSAGE_ID', ''), recipients: recipients, verdicts: verdicts).run
    puts "#{record.message_id}: #{record.status}#{" (#{record.reason})" if record.reason}"
  end

  desc 'Deletes the records of received email older than the given days: prune_records[90] (default 90)'
  task :prune_records, [:days] => :environment do |_task, args|
    days = args[:days].presence || AwsSesReceivedMail::KEEP_DAYS
    puts "deleted #{AwsSesReceivedMail.prune(days)} record(s) older than #{days} days"
  end
end
