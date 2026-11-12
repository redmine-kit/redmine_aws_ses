# frozen_string_literal: true

require_relative '../test_helper'
require_relative 'mail_bucket_helper'

module RedmineAws
  module SES
    # A reply let in by a registered forwarder (its From not authenticated)
    # may add a note only to the project the envelope recipient chose, for
    # each "Author of forwarded email": a reply to another project's issue is
    # not fetched and leaves no note.
    class ReceiveForwardedReplyTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper
      include RedmineAws::SES::MailBucketHelper

      SRS = 'support+SRS=44ldt=IX=somenet.foo=rhill@company.example'
      DMARC_FAIL = PASS.merge(dmarc: 'FAIL')
      # How the reply names the issue: the subject, In-Reply-To or References
      # (MailHandler::MESSAGE_ID_RE).
      NOTIFICATION = '<redmine.issue-%d.20261101000000.1@redmine.example.com>'
      REPLIES = {
        subject: ->(id) { { subject: "Re: [Project - Bug ##{id}] Oven" } },
        in_reply_to: ->(id) { { headers: { 'In-Reply-To' => format(NOTIFICATION, id) } } },
        references: ->(id) { { headers: { 'References' => format(NOTIFICATION, id) } } }
      }.freeze

      def setup
        [Role.non_member, Role.anonymous].each { |role| role.add_permission!(:view_issues, :add_issue_notes) }
      end

      def test_a_reply_to_the_routed_project_is_a_note
        AwsSesProjectMailSetting::FORWARDED_AUTHORS.each do |author|
          REPLIES.each do |how, reply|
            record = nil
            assert_difference('Journal.count', 1, [author, how].inspect) { record = forwarded_reply(1, author, reply) }

            assert_equal ['imported', 'Journal', 1], [record.status, record.target_type, record.issue_id]
          end
        end
      end

      def test_a_reply_to_another_project_is_not_fetched
        AwsSesProjectMailSetting::FORWARDED_AUTHORS.each do |author|
          REPLIES.each do |how, reply|
            record = nil
            assert_no_difference(%w[Journal.count Issue.count], [author, how].inspect) do
              record = forwarded_reply(4, author, reply)
            end

            assert_equal %w[dropped forwarded_reply], [record.status, record.reason], [author, how].inspect
          end
        end
      end

      private

      # rhill's reply to issue id, through company.example's forwarding.
      def forwarded_reply(id, author, reply)
        project_setting.update!(forwarders: 'company.example', forwarded_author: author, unknown_user: 'accept')
        args = reply.call(id)
        raw = ses_message(from: 'rhill@somenet.foo', to: 'support@company.example',
                          subject: args[:subject] || 'Re: Oven', headers: args[:headers] || {})
        receive(raw, verdicts: DMARC_FAIL, envelope_from: SRS)
      end
    end
  end
end
