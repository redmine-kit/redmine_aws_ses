# frozen_string_literal: true

# The tasks' work is in RedmineAws::SES::Tasks.
namespace :redmine_aws_ses do
  desc 'Imports one message that SES stored in the mail bucket (MESSAGE_ID, SES_RECIPIENTS, SES_MAIL_FROM, ' \
       'SES_*_VERDICT)'
  task receive_mail: :environment do
    puts RedmineAws::SES::Tasks.receive_mail(ENV)
  end

  desc 'Reads the state of SES and DNS for the email tabs of the AWS administration page (on a schedule)'
  task refresh: :environment do
    line, ok = RedmineAws::SES::Tasks.refresh
    ok ? puts(line) : abort(line)
  end

  desc 'Deletes the records of received email older than the given days: prune_records[90] (default 90)'
  task :prune_records, [:days] => :environment do |_task, args|
    puts RedmineAws::SES::Tasks.prune_records(args[:days])
  end
end
