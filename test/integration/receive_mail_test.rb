# frozen_string_literal: true

require_relative '../test_helper'
require_relative 'mail_bucket_helper'

module RedmineAws
  module SES
    # The import on S3, with messages as SES stores them: the project, the checks and the rake task.
    class ReceiveMailTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper
      include RedmineAws::SES::MailBucketHelper

      def test_an_issue_is_created_in_the_project_of_the_recipient
        record = nil
        assert_difference('Issue.count', 1) { record = receive(ses_message) }
        issue = Issue.order(:id).last

        assert_equal %w[ecookbook jsmith], [issue.project.identifier, issue.author.login]
        assert_equal 'Feature request', issue.tracker.name
        assert_equal issue.id, record.issue_id
      end

      def test_the_record_of_an_imported_message
        record = receive(ses_message)

        assert_equal 'imported', record.status
        assert_equal ["processed/#{record.message_id}"], keys
        assert_equal PASS, record.verdicts
      end

      def test_bcc_recipients_from_the_event
        record = receive(ses_message(to: 'someone@other.example'))

        assert_equal 'imported', record.status
      end

      def test_a_project_keyword_cannot_change_the_project
        receive(ses_message(body: "Project: onlinestore\n\nMoved?"))

        assert_equal 'ecookbook', Issue.order(:id).last.project.identifier
      end

      # reason => the event's values, or the message.
      DROPPED = { 'dmarc' => { verdicts: PASS.merge(dmarc: 'FAIL') }, 'spam' => { verdicts: PASS.merge(spam: 'FAIL') },
                  'virus' => { verdicts: PASS.merge(virus: 'FAIL') }, 'no_verdict' => { verdicts: nil },
                  'auto_reply' => { headers: { 'Auto-Submitted' => 'auto-replied' } },
                  'no_project' => { recipients: ["nobody@#{DOMAIN}"] } }.freeze

      def test_dropped_messages_stay_in_inbound
        DROPPED.each do |reason, args|
          args = args.dup
          raw = ses_message(headers: args.delete(:headers) || {})
          record = nil
          assert_no_difference('Issue.count') { record = receive(raw, **args) }

          assert_equal ['dropped', reason], [record.status, record.reason], reason
          assert_includes keys, "inbound/#{record.message_id}"
        end
      end

      def test_headers_cannot_pass_the_checks
        forged = { 'X-SES-Spam-Verdict' => 'PASS', 'X-SES-Virus-Verdict' => 'PASS',
                   'Authentication-Results' => 'amazonses.com; spf=pass; dkim=pass; dmarc=pass' }
        record = receive(ses_message(headers: forged), verdicts: PASS.merge(dmarc: 'FAIL'))

        assert_equal %w[dropped dmarc], [record.status, record.reason]
      end

      ALLOW_ALL = { 'import_spam' => '1', 'import_without_dmarc_pass' => '1' }.freeze

      def test_settings_can_import_spam_and_email_that_fails_dmarc
        record = nil
        assert_difference('Issue.count', 1) do
          record = receive(ses_message, verdicts: PASS.merge(spam: 'FAIL', dmarc: 'FAIL'), **ALLOW_ALL)
        end

        assert_equal 'imported', record.status
        assert_equal %w[FAIL FAIL], record.verdicts.values_at(:spam, :dmarc)
      end

      def test_a_virus_is_never_imported
        record = receive(ses_message, verdicts: PASS.merge(virus: 'FAIL'), **ALLOW_ALL)

        assert_equal %w[dropped virus], [record.status, record.reason]
        assert_equal 'FAIL', record.verdicts[:virus]
      end

      def test_recipients_come_from_the_event_not_the_headers
        record = receive(ses_message(to: "ecookbook@#{DOMAIN}"), recipients: ['someone@other.example'])

        assert_equal %w[dropped no_project], [record.status, record.reason]
      end

      def test_a_sender_redmine_does_not_accept
        record = receive(ses_message(from: 'stranger@other.example'))

        assert_equal %w[dropped import_error], [record.status, record.reason]
      end

      # Anyone can send to the domain: headers with raw 8-bit text (Shift_JIS
      # without MIME encoding) and a date that is not one still leave a record.
      def test_headers_that_are_not_utf8
        record = receive(sjis_message)

        assert_predicate record, :persisted?
        assert record.subject.start_with?('Re: ')
        assert_predicate record.subject, :valid_encoding?
        assert_not_nil record.received_at
      end

      # The mail gem cannot parse the address, and keeps the header as it is.
      def test_a_sender_that_is_not_utf8
        record = receive(sjis_message)

        assert_includes record.mail_from, '<jsmith@somenet.foo>'
        assert_predicate record.mail_from, :valid_encoding?
      end

      def test_message_ids_are_checked
        assert_raises(ArgumentError) { RedmineAws::SES::Receiver.new('../etc/passwd', bucket: @bucket) }
      end

      private

      # Raw 8-bit Shift_JIS in the subject and the sender, and a date that is
      # not one.
      def sjis_message
        sjis = '日本語'.encode('Shift_JIS').b
        raw = ses_message(subject: "Re: #{sjis}").b
        raw.sub('From: John Smith', "From: #{sjis}").sub(/^Date: .*$/, 'Date: not a date')
      end
    end
  end
end
