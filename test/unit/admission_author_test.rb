# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # The author of forwarded email (Admission#author), table-driven: the
    # original sender is an administrator, a member of the project, a
    # registered user outside it, or unknown to Redmine; for each setting of
    # forwarded_author, for a member's forward and for automatic forwarding
    # through a registered forwarder. jsmith (a member) forwards.
    class AdmissionAuthorTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper

      FORWARD = File.expand_path('../fixtures/forwarded/gmail_en.eml', __dir__)
      SENDERS = %w[admin@somenet.foo dlopper@somenet.foo rhill@somenet.foo customer@client.example].freeze
      SRS = 'support+SRS=44ldt=IX=client.example=customer@company.example'

      # [kind, setting, unknown_user] => the author for each of SENDERS
      # (logins; anonymous; nil when no one may be the author).
      AUTHORS = {
        [:member, 'external', 'ignore'] => %w[jsmith jsmith rhill jsmith],
        [:member, 'external', 'accept'] => %w[jsmith jsmith rhill anonymous],
        [:member, 'registered', 'ignore'] => %w[admin dlopper rhill jsmith],
        [:member, 'registered', 'create'] => %w[admin dlopper rhill anonymous],
        [:member, 'forwarder', 'accept'] => %w[jsmith jsmith jsmith jsmith],
        [:automatic, 'external', 'accept'] => %w[anonymous anonymous rhill anonymous],
        [:automatic, 'external', 'ignore'] => [nil, nil, 'rhill', nil],
        [:automatic, 'registered', 'accept'] => %w[admin dlopper rhill anonymous],
        [:automatic, 'forwarder', 'accept'] => %w[anonymous anonymous anonymous anonymous],
        [:automatic, 'forwarder', 'ignore'] => [nil, nil, nil, nil]
      }.freeze

      def test_the_author_for_each_sender_and_setting
        AUTHORS.each do |(kind, setting, unknown_user), authors|
          setting_for(setting, unknown_user)
          SENDERS.zip(authors).each do |sender, expected|
            actual = login(admission(kind, sender).author)

            assert_equal [expected], [actual], [kind, setting, unknown_user, sender].inspect
          end
        end
      end

      # Automatic forwarding without an author is not imported.
      def test_no_author_is_a_reason
        setting_for('forwarder', 'ignore')

        assert_equal 'forwarded_author', admission(:automatic, 'rhill@somenet.foo').reason
      end

      # Headers that name another sender change nothing: the author comes
      # from From, through the setting.
      def test_forged_headers
        setting_for('external', 'accept')
        forged = { 'Sender' => 'rhill@somenet.foo', 'Reply-To' => 'rhill@somenet.foo',
                   'X-Original-From' => 'rhill@somenet.foo' }
        raw = ses_message(from: 'admin@somenet.foo', headers: forged)

        assert_equal 'anonymous', login(admission(:automatic, nil, raw: raw).author)
      end

      # A message that passed DMARC is not forwarded: Redmine's MailHandler
      # takes its sender.
      def test_mail_that_passed_dmarc_has_no_chosen_author
        setting_for('forwarder', 'accept')

        assert_nil admission(:automatic, 'admin@somenet.foo', verdicts: PASS).author
      end

      private

      def setting_for(author, unknown_user)
        AwsSesProjectMailSetting.find_or_initialize_by(project_id: 1)
                                .update!(receive: true, unknown_user: unknown_user, forwarded_author: author,
                                         import_forwarded: true, forwarders: 'company.example')
      end

      def admission(kind, sender, raw: nil, verdicts: PASS.merge(dmarc: 'FAIL'))
        raw ||= raw_message(kind, sender)
        record = AwsSesReceivedMail.new(message_id: 'm1', recipients: "ecookbook@#{DOMAIN}")
        record.verdicts = kind == :member ? PASS : verdicts
        record.envelope_from = kind == :member ? 'jsmith@somenet.foo' : SRS
        with_ses_settings('per_project_addresses' => '1') do
          RedmineAws::SES::Admission.new(record, Mail.new(raw)).tap(&:reason)
        end
      end

      def raw_message(kind, sender)
        kind == :member ? File.binread(FORWARD).sub('customer@client.example', sender) : ses_message(from: sender)
      end

      def login(user)
        user&.anonymous? ? 'anonymous' : user&.login
      end
    end
  end
end
