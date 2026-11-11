# frozen_string_literal: true

require_relative '../test_helper'
require_relative 'mail_bucket_helper'

module RedmineAws
  module SES
    # Runs of the import: the size limit, runs for the same message, re-imports and the records.
    class ReceiveMailRunsTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper
      include RedmineAws::SES::MailBucketHelper

      # SES's limit (40 MB); the record keeps the headers.
      def test_a_message_larger_than_the_limit
        raw = ses_message(subject: 'Large', body: 'x' * 3_000)
        record = nil
        assert_no_difference('Issue.count') { record = receive(raw, max_bytes: 2_000) }

        assert_equal %w[dropped too_large], [record.status, record.reason]
        assert_equal %w[Large jsmith@somenet.foo], [record.subject, record.mail_from]
        assert_includes keys, "inbound/#{record.message_id}"
      end

      # One mail never creates two issues: a second run (SES's retry, a
      # re-import) finds the mail imported, and its issue still there.
      def test_a_second_run_does_not_import_again
        record = receive(ses_message)
        assert_no_difference('Issue.count') { receive(nil, id: record.message_id) }

        assert_equal 'imported', record.reload.status
      end

      # A conflict with a concurrent transaction is run again once.
      def test_a_serialization_failure_is_retried
        real = AwsSesReceivedMail.lock
        AwsSesReceivedMail.stubs(:lock).raises(ActiveRecord::SerializationFailure, 'conflict').then.returns(real)
        record = nil
        assert_difference('Issue.count', 1) { record = receive(ses_message) }

        assert_equal 'imported', record.status
      end

      # No transaction inside the import's own: a message Redmine refuses is
      # rolled back as a whole and recorded in a transaction of its own (some
      # databases have no savepoints). The tests' transaction makes the
      # import's a savepoint, so a nested one would be the second level.
      def test_no_nested_savepoints
        statements = []
        callback = ->(*, payload) { statements << payload[:sql] if payload[:sql].to_s.start_with?('SAVEPOINT') }
        record = ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          receive(ses_message(from: 'stranger@other.example'))
        end

        assert_equal %w[dropped import_error], [record.status, record.reason]
        assert_equal ['SAVEPOINT active_record_1'], statements.uniq
      end

      # Two first runs at the same time meet at the unique index: the second
      # rolls back what it created and finds the first's record.
      def test_two_first_runs
        record = receive(ses_message)
        real = AwsSesReceivedMail.lock
        AwsSesReceivedMail.stubs(:lock).returns(AwsSesReceivedMail.none).then.returns(real)
        again = nil
        assert_no_difference(%w[Issue.count AwsSesReceivedMail.count]) do
          again = receive(nil, id: record.message_id)
        end

        assert_equal record.id, again.id
      end

      def test_reimport_from_processed_reuses_the_recipients_and_verdicts
        record = receive(ses_message(to: 'x@other.example'))
        Issue.find(record.issue_id).destroy
        with_env('REDMINE_MAIL_BUCKET' => @bucket) do
          with_ses_settings('per_project_addresses' => '1') do
            assert_difference('Issue.count', 1) { AwsSesReimportMailJob.perform_now(record.message_id) }
          end
        end

        assert_equal 1, AwsSesReceivedMail.where(message_id: record.message_id).count
      end

      def test_records_are_kept_for_90_days
        AwsSesReceivedMail.create!(message_id: 'old', status: 'imported', created_at: 91.days.ago)
        AwsSesReceivedMail.create!(message_id: 'new', status: 'imported')
        assert_equal 1, AwsSesReceivedMail.prune

        assert_equal %w[new], AwsSesReceivedMail.pluck(:message_id)
        AwsSesReceivedMail.find_by(message_id: 'new').update_column(:created_at, 31.days.ago)

        assert_equal 1, AwsSesReceivedMail.prune(30)
      end
    end
  end
end
