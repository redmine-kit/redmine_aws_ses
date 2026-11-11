# frozen_string_literal: true

require_relative '../test_helper'
require_relative 'mail_bucket_helper'
require 'rake'

module RedmineAws
  module SES
    # The rake task redmine_aws_ses:receive_mail with the values of an SES
    # event, as Serverless's task handler sets them.
    class ReceiveMailTaskTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper
      include RedmineAws::SES::MailBucketHelper

      # The variables that Serverless's task handler sets from an SES event
      # (test/fixtures/ses_event.json), given to the rake task.
      def event_env(id, **changes)
        event = JSON.parse(File.read(File.expand_path('../fixtures/ses_event.json', __dir__)))
        receipt = event.dig('Records', 0, 'ses', 'receipt').merge(changes.transform_keys(&:to_s))
        { 'MESSAGE_ID' => id, 'SES_RECIPIENTS' => receipt['recipients'].join(','),
          'SES_SPAM_VERDICT' => receipt.dig('spamVerdict', 'status'),
          'SES_VIRUS_VERDICT' => receipt.dig('virusVerdict', 'status'),
          'SES_DMARC_VERDICT' => receipt.dig('dmarcVerdict', 'status'),
          'SES_SPF_VERDICT' => receipt.dig('spfVerdict', 'status'),
          'SES_DKIM_VERDICT' => receipt.dig('dkimVerdict', 'status'), 'SES_DMARC_POLICY' => receipt['dmarcPolicy'],
          'SES_MAIL_FROM' => event.dig('Records', 0, 'ses', 'mail', 'source') }
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

        assert_equal %w[imported NONE], [record.status, record.dmarc_policy]
        assert_equal 'jsmith@somenet.foo', record.envelope_from
      end

      def test_the_rake_task_with_a_failed_verdict
        dropped = rake_receive(event_env(store(ses_message), dmarcVerdict: { 'status' => 'FAIL' }))

        assert_equal %w[dropped dmarc], [dropped.status, dropped.reason]
      end
    end
  end
end
