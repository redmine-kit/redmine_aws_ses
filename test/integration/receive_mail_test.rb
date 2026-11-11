# frozen_string_literal: true

require_relative '../test_helper'
require 'rake'

module RedmineAws
  module SES
    # The import on moto's S3, with messages as SES stores them.
    class ReceiveMailTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper

      def setup
        @s3 = ::Aws::S3::Client.new(endpoint: ENV.fetch('AWS_ENDPOINT_URL'), force_path_style: true)
        @bucket = "redmine-mail-#{SecureRandom.hex(4)}"
        @s3.create_bucket(bucket: @bucket)
        RedmineAws::SES::Clients.s3 = @s3
        ActionMailer::Base.deliveries.clear
      end

      def teardown
        return unless @bucket

        @s3.list_objects_v2(bucket: @bucket).contents.each { |o| @s3.delete_object(bucket: @bucket, key: o.key) }
        @s3.delete_bucket(bucket: @bucket)
      end

      def store(raw)
        id = SecureRandom.hex(10)
        @s3.put_object(bucket: @bucket, key: "inbound/#{id}", body: raw)
        id
      end

      def keys
        @s3.list_objects_v2(bucket: @bucket).contents.map(&:key)
      end

      def receive(raw, recipients: ["ecookbook@#{DOMAIN}"], verdicts: PASS, **settings)
        id = store(raw)
        with_env('REDMINE_MAIL_BUCKET' => @bucket) do
          with_ses_settings({ 'per_project_addresses' => '1' }.merge(settings)) do
            AwsSesProjectMailSetting.find_or_create_by!(project_id: 1) do |setting|
              setting.receive = true
              setting.tracker_id = 2
            end
            RedmineAws::SES::Receiver.new(id, recipients: recipients, verdicts: verdicts).run
          end
        end
      end

      def test_an_issue_is_created_in_the_project_of_the_recipient
        record = nil
        assert_difference('Issue.count', 1) { record = receive(ses_message) }
        issue = Issue.order(:id).last

        assert_equal 'imported', record.status
        assert_equal 'ecookbook', issue.project.identifier
        assert_equal 'Feature request', issue.tracker.name
        assert_equal 'jsmith', issue.author.login
        assert_equal issue.id, record.issue_id
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

      def test_dropped_messages_stay_in_inbound
        { 'dmarc' => { verdicts: PASS.merge(dmarc: 'FAIL') }, 'spam' => { verdicts: PASS.merge(spam: 'FAIL') },
          'virus' => { verdicts: PASS.merge(virus: 'FAIL') }, 'no_verdict' => { verdicts: nil },
          'auto_reply' => { raw: ses_message(headers: { 'Auto-Submitted' => 'auto-replied' }) },
          'no_project' => { recipients: ["nobody@#{DOMAIN}"] } }.each do |reason, args|
          record = nil
          assert_no_difference('Issue.count') do
            record = receive(args.delete(:raw) || ses_message, **args)
          end

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

      def test_settings_can_import_spam_and_email_that_fails_dmarc
        record = nil
        assert_difference('Issue.count', 1) do
          record = receive(ses_message, verdicts: PASS.merge(spam: 'FAIL', dmarc: 'FAIL'),
                                        'import_spam' => '1', 'import_without_dmarc_pass' => '1')
        end
        assert_equal 'imported', record.status
        assert_equal %w[FAIL FAIL], record.verdicts.values_at(:spam, :dmarc)

        record = receive(ses_message, verdicts: PASS.merge(virus: 'FAIL'),
                                      'import_spam' => '1', 'import_without_dmarc_pass' => '1')

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

      # The variables that Serverless's task handler sets from an SES event
      # (test/fixtures/ses_event.json), given to the rake task.
      def event_env(id, **changes)
        receipt = JSON.parse(File.read(File.expand_path('../fixtures/ses_event.json', __dir__)))
                      .dig('Records', 0, 'ses', 'receipt').merge(changes.transform_keys(&:to_s))
        { 'MESSAGE_ID' => id, 'SES_RECIPIENTS' => receipt['recipients'].join(','),
          'SES_SPAM_VERDICT' => receipt.dig('spamVerdict', 'status'),
          'SES_VIRUS_VERDICT' => receipt.dig('virusVerdict', 'status'),
          'SES_DMARC_VERDICT' => receipt.dig('dmarcVerdict', 'status'),
          'SES_SPF_VERDICT' => receipt.dig('spfVerdict', 'status'),
          'SES_DKIM_VERDICT' => receipt.dig('dkimVerdict', 'status'), 'SES_DMARC_POLICY' => receipt['dmarcPolicy'] }
      end

      def rake_receive(env)
        Rails.application.load_tasks unless Rake::Task.task_defined?('redmine_aws_ses:receive_mail')
        task = Rake::Task['redmine_aws_ses:receive_mail']
        task.reenable
        with_env(env.merge('REDMINE_MAIL_BUCKET' => @bucket)) do
          with_ses_settings('per_project_addresses' => '1') do
            AwsSesProjectMailSetting.find_or_create_by!(project_id: 1) { |setting| setting.receive = true }
            capture_io { task.invoke }
          end
        end
        AwsSesReceivedMail.find_by!(message_id: env['MESSAGE_ID'])
      end

      def test_the_rake_task_with_an_ses_event
        id = store(ses_message(to: 'someone@other.example'))
        record = nil
        assert_difference('Issue.count', 1) { record = rake_receive(event_env(id)) }

        assert_equal 'imported', record.status
        assert_equal 'NONE', record.dmarc_policy
        dropped = rake_receive(event_env(store(ses_message), dmarcVerdict: { 'status' => 'FAIL' }))

        assert_equal %w[dropped dmarc], [dropped.status, dropped.reason]
      end

      def test_message_ids_are_checked
        assert_raises(ArgumentError) { RedmineAws::SES::Receiver.new('../etc/passwd', bucket: @bucket) }
      end
    end
  end
end
