# frozen_string_literal: true

require_relative '../test_helper'
require File.join(Redmine::Plugin.find(:redmine_aws).directory, 'test/support/redmine_aws/screenshot_case')

module RedmineAws
  module SES
    # The screens of docs/admin.md: the Sending email and Receiving email tabs
    # and a project's Email tab, for the domain redmine.example.com. SES
    # answers with SDK response stubs; the account, the addresses, the bucket
    # and the mail are examples.
    class ScreenshotsTest < RedmineAws::ScreenshotCase
      self.docs = File.expand_path('../../docs', __dir__)

      DOMAIN = 'redmine.example.com'

      PAGES = [
        ['/admin/aws/mail_sending', 'mail-sending', '#content h3', nil],
        ['/admin/aws/mail_receiving', 'mail-receiving', '#content h3', nil],
        ['/projects/ecookbook/settings/aws_ses_mail', 'project-mail', '#tab-content-aws_ses_mail',
         '#tab-content-aws_ses_mail']
      ].freeze

      SES_STUBS = {
        get_account: { production_access_enabled: true, sending_enabled: true, enforcement_status: 'HEALTHY',
                       send_quota: { max_24_hour_send: 50_000.0, max_send_rate: 14.0, sent_last_24_hours: 312.0 } },
        get_email_identity: { verified_for_sending_status: true, dkim_attributes: { status: 'SUCCESS' } }
      }.freeze

      # From, subject, recipient, project, status, reason, target, verdicts
      # (spam, virus, DMARC), and how long ago.
      MAILS = [
        ['jsmith@somenet.foo', 'Oven does not heat up', 'cookbook', 1, 'imported', nil, ['Issue', 1],
         %w[PASS PASS PASS], 20.minutes],
        ['offers@mailer.example.net', 'You have won a prize', 'redmine', nil, 'dropped', 'spam', [],
         %w[FAIL PASS GRAY], 2.hours],
        ['billing@lookalike.example.org', 'Invoice overdue', 'cookbook', 1, 'dropped', 'dmarc', [],
         %w[PASS PASS FAIL], 5.hours]
      ].freeze

      def setup
        super
        @saved_bucket = ENV.fetch('REDMINE_MAIL_BUCKET', nil)
        ENV['REDMINE_MAIL_BUCKET'] = 'redmine-mail-111122223333'
        configure_plugin
        @saved_ses = RedmineAws::SES::Clients.instance_variable_get(:@ses)
        RedmineAws::SES::Clients.ses = ses_client
        store_state
        record_received_mail
      end

      def teardown
        RedmineAws::SES::Clients.ses = @saved_ses
        @saved_bucket ? ENV['REDMINE_MAIL_BUCKET'] = @saved_bucket : ENV.delete('REDMINE_MAIL_BUCKET')
      end

      def test_screens
        each_language do |language|
          PAGES.each do |path, name, ready, selector|
            visit path
            assert_selector ready
            shoot name, language, **{ selector: selector }.compact
          end
        end
      end

      private

      def configure_plugin
        Setting.mail_from = "redmine@#{DOMAIN}"
        Setting.plugin_redmine_aws_ses = RedmineAws::SES::DEFAULTS.merge(
          'per_project_addresses' => '1', 'project_senders' => '1', 'default_project' => 'ecookbook'
        )
        AwsSesProjectMailSetting.create!(project: Project.find(1), receive: true, tracker_id: 1, priority_id: 5,
                                         unknown_user: 'accept', forwarders: 'company.example')
        AwsSesProjectMailSetting.create!(project: Project.find(2), receive: true)
      end

      def ses_client
        suppressed = [{ email_address: 'dlopper@somenet.foo', reason: 'BOUNCE', last_update_time: 2.days.ago }]
        ::Aws::SESV2::Client.new(region: 'ap-northeast-1', stub_responses: SES_STUBS.merge(
          list_suppressed_destinations: { suppressed_destination_summaries: suppressed }
        ))
      end

      # The state as a refresh stores it, with the MX record that SES
      # receiving needs instead of a DNS lookup.
      def store_state
        state = RedmineAws::SES::Account.new(client: ses_client, domain: DOMAIN)
        state.define_singleton_method(:mx) { ['inbound-smtp.ap-northeast-1.amazonaws.com'] }
        AwsSesSnapshot.refresh!(state)
      end

      def record_received_mail
        MAILS.each_with_index do |(from, subject, to, project, status, reason, (type, id), verdicts, ago), index|
          AwsSesReceivedMail.create!(
            message_id: "screenshot-#{index}@#{DOMAIN}", s3_key: "inbound/screenshot-#{index}", mail_from: from,
            subject: subject, recipients: "#{to}@#{DOMAIN}", project_id: project, status: status, reason: reason,
            target_type: type, target_id: id, received_at: ago.ago, processed_at: ago.ago + 3.seconds,
            verdicts: { spam: verdicts[0], virus: verdicts[1], dmarc: verdicts[2], dmarc_policy: 'REJECT',
                        spf: 'PASS', dkim: 'PASS' }
          )
        end
      end
    end
  end
end
