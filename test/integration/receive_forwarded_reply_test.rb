# frozen_string_literal: true

require_relative '../test_helper'
require_relative 'mail_bucket_helper'

module RedmineAws
  module SES
    # A reply let in by a registered forwarder (its From not authenticated)
    # may reach only the project the envelope recipient chose, for each kind
    # of reply MailHandler knows and each "Author of forwarded email": a
    # reply to another project is not fetched and creates nothing.
    class ReceiveForwardedReplyTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper
      include RedmineAws::SES::MailBucketHelper

      SRS = 'support+SRS=44ldt=IX=somenet.foo=rhill@company.example'
      NOTIFICATION = '<redmine.%s-%d.20261101000000.1@redmine.example.com>'
      # kind => how a reply names it: by its subject (issues, forum
      # messages), In-Reply-To or References.
      WAYS = {
        'issue' => %i[subject in_reply_to references], 'journal' => %i[in_reply_to references],
        'message' => %i[subject in_reply_to references], 'news' => %i[in_reply_to references],
        'comment' => %i[in_reply_to references]
      }.freeze
      SUBJECTS = { 'issue' => 'Re: [Project - Bug #%d] Oven', 'message' => 'Re: [Board - msg%d] Oven' }.freeze
      CREATED = %w[Journal.count Message.count Comment.count Issue.count].freeze

      def setup
        [Role.non_member, Role.anonymous].each do |role|
          role.add_permission!(:view_issues, :add_issue_notes, :view_messages, :add_messages, :view_news, :comment_news)
        end
        @routed = { 'issue' => 1, 'journal' => 1, 'message' => 1, 'news' => 1, 'comment' => 1 }
        @other = { 'issue' => 4, 'journal' => other_journal.id, 'message' => 7, 'news' => 3,
                   'comment' => other_comment.id }
      end

      def test_a_reply_within_the_routed_project
        each_case(@routed) do |label, raw|
          record = receive_reply(raw)

          assert_equal 'imported', record.status, label
        end
      end

      def test_a_reply_to_another_project_is_not_fetched
        each_case(@other) do |label, raw|
          record = nil
          assert_no_difference(CREATED, label) { record = receive_reply(raw) }

          assert_equal %w[dropped forwarded_reply], [record.status, record.reason], label
        end
      end

      # A kind of reply the guard does not know (here wiki pages, which
      # MailHandler does not handle either) is refused too.
      def test_a_reply_of_an_unknown_kind
        each_author do |author|
          raw = reply_message(headers: { 'In-Reply-To' => format(NOTIFICATION, 'wiki_page', 1) })

          assert_equal 'forwarded_reply', receive_reply(raw).reason, author
        end
      end

      private

      def each_case(ids)
        each_author do |author|
          WAYS.each do |kind, ways|
            ways.each { |way| yield [author, kind, way].inspect, reply_message(**reply(kind, way, ids[kind])) }
          end
        end
      end

      def each_author
        AwsSesProjectMailSetting::FORWARDED_AUTHORS.each do |author|
          project_setting.update!(forwarders: 'company.example', forwarded_author: author, unknown_user: 'accept')
          yield author
        end
      end

      def reply(kind, way, id)
        return { subject: format(SUBJECTS[kind], id) } if way == :subject

        { headers: { way == :in_reply_to ? 'In-Reply-To' : 'References' => format(NOTIFICATION, kind, id) } }
      end

      # rhill's reply, through company.example's forwarding.
      def reply_message(subject: 'Re: Oven', headers: {})
        ses_message(from: 'rhill@somenet.foo', to: 'support@company.example', subject: subject, headers: headers)
      end

      def receive_reply(raw)
        receive(raw, verdicts: PASS.merge(dmarc: 'FAIL'), envelope_from: SRS)
      end

      def other_journal
        Journal.create!(journalized: Issue.find(4), user: User.find(2), notes: 'A note in OnlineStore')
      end

      def other_comment
        Comment.create!(commented: News.find(3), author: User.find(2), content: 'A comment in OnlineStore')
      end
    end
  end
end
