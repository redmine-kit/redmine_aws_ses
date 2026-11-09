# frozen_string_literal: true

require_relative 'screenshot_case'

# The screens of docs/admin.md: the Sending email and Receiving email tabs and
# a project's Mail tab, for the domain redmine.example.com. SES answers with
# SDK response stubs; the account, the addresses, the bucket and the mail are
# examples.
class RedmineServerlessSesScreens < ScreenshotCase
  DOMAIN = 'redmine.example.com'

  # The MX record that SES receiving needs, instead of a DNS lookup.
  module FixedMx
    def mx_records
      ['inbound-smtp.ap-northeast-1.amazonaws.com']
    end
  end
  ServerlessMailReceivingController.prepend(FixedMx)

  def setup
    super
    @saved_bucket = ENV.fetch('REDMINE_MAIL_BUCKET', nil)
    ENV['REDMINE_MAIL_BUCKET'] = 'redmine-mail-111122223333'
    Setting.mail_from = "redmine@#{DOMAIN}"
    Setting.plugin_redmine_serverless_ses = RedmineServerlessSes::DEFAULTS.merge(
      'per_project_addresses' => '1', 'project_senders' => '1', 'default_project' => 'ecookbook'
    )
    @saved_ses = RedmineServerlessSes::Clients.instance_variable_get(:@ses)
    RedmineServerlessSes::Clients.ses = ses_client
    Rails.cache.clear
    ServerlessProjectMailSetting.create!(project: Project.find(1), receive: true, alias_name: 'cookbook',
                                         tracker_id: 1, priority_id: 5, unknown_user: 'accept')
    ServerlessProjectMailSetting.create!(project: Project.find(2), receive: true)
    record_received_mail
  end

  def teardown
    RedmineServerlessSes::Clients.ses = @saved_ses
    @saved_bucket ? ENV['REDMINE_MAIL_BUCKET'] = @saved_bucket : ENV.delete('REDMINE_MAIL_BUCKET')
  end

  def test_screens
    each_language do |language|
      visit '/admin/serverless/mail_sending'
      assert_selector '#content h3'
      shoot 'mail-sending', language

      visit '/admin/serverless/mail_receiving'
      assert_selector '#content h3'
      shoot 'mail-receiving', language

      visit '/projects/ecookbook/settings/serverless_mail'
      assert_selector '#tab-content-serverless_mail'
      shoot 'project-mail', language, selector: '#tab-content-serverless_mail'
    end
  end

  private

  def ses_client
    client = Aws::SESV2::Client.new(stub_responses: true, region: 'ap-northeast-1')
    client.stub_responses(:get_account, production_access_enabled: true, sending_enabled: true,
                                        enforcement_status: 'HEALTHY',
                                        send_quota: { max_24_hour_send: 50_000.0, max_send_rate: 14.0,
                                                      sent_last_24_hours: 312.0 })
    client.stub_responses(:get_email_identity, verified_for_sending_status: true,
                                               dkim_attributes: { status: 'SUCCESS' })
    client.stub_responses(:list_suppressed_destinations, suppressed_destination_summaries: [
                            { email_address: 'dlopper@somenet.foo', reason: 'BOUNCE',
                              last_update_time: 2.days.ago }
                          ])
    client
  end

  def record_received_mail
    now = Time.current
    [
      ['jsmith@somenet.foo', 'Oven does not heat up', "cookbook@#{DOMAIN}", 1, 'imported', nil, 'Issue', 1,
       %w[PASS PASS PASS], 20.minutes],
      ['offers@mailer.example.net', 'You have won a prize', "redmine@#{DOMAIN}", nil, 'dropped', 'spam', nil, nil,
       %w[FAIL PASS NONE], 2.hours],
      ['billing@lookalike.example.org', 'Invoice overdue', "cookbook@#{DOMAIN}", 1, 'dropped', 'dmarc', nil, nil,
       %w[PASS PASS FAIL], 5.hours]
    ].each_with_index do |(from, subject, to, project, status, reason, type, id, (spam, virus, dmarc), ago), index|
      ServerlessReceivedMail.create!(
        message_id: "screenshot-#{index}@#{DOMAIN}", s3_key: "inbound/screenshot-#{index}", mail_from: from,
        subject: subject, recipients: to, spam_verdict: spam, virus_verdict: virus, dmarc_verdict: dmarc,
        dmarc_policy: 'REJECT', spf_verdict: 'PASS', dkim_verdict: 'PASS', project_id: project,
        status: status, reason: reason, target_type: type, target_id: id,
        received_at: now - ago, processed_at: now - ago + 3.seconds
      )
    end
  end
end
