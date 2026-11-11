# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # The decisions about a received message. Only the SES event (verdicts,
    # envelope recipients, envelope sender) and Redmine decide; headers never
    # do.
    class AdmissionTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper

      FORWARDED = File.expand_path('../fixtures/forwarded/gmail_en.eml', __dir__)

      def setup
        @setting = AwsSesProjectMailSetting.create!(project_id: 1, receive: true, unknown_user: 'accept',
                                                    forwarders: "support@company.example\nforwarder.example")
      end

      def admission(raw = ses_message, verdicts: PASS, envelope_from: 'jsmith@somenet.foo',
                    recipients: "ecookbook@#{DOMAIN}", **settings)
        record = AwsSesReceivedMail.new(message_id: 'm1', recipients: recipients, envelope_from: envelope_from)
        record.verdicts = verdicts
        result = nil
        with_ses_settings({ 'per_project_addresses' => '1' }.merge(settings)) do
          result = RedmineAws::SES::Admission.new(record, Mail.new(raw))
          result.reason
          result.forward
        end
        result
      end

      DMARC_FAIL = PASS.merge(dmarc: 'FAIL')
      SRS = 'support+SRS=44ldt=IX=fabrikam.com=bob@company.example'
      # [verdicts, envelope sender] => reason
      AUTOMATIC = {
        [PASS, 'jsmith@somenet.foo'] => nil, [DMARC_FAIL, SRS] => nil, [DMARC_FAIL, 'bounce@forwarder.example'] => nil,
        [DMARC_FAIL, 'jsmith@somenet.foo'] => 'dmarc', [DMARC_FAIL, nil] => 'dmarc',
        [DMARC_FAIL.merge(spf: 'FAIL'), SRS] => 'forwarder_spf',
        [DMARC_FAIL.merge(spf: 'GRAY'), 'bounce@forwarder.example'] => 'forwarder_spf',
        [DMARC_FAIL.merge(spam: 'FAIL'), SRS] => 'spam', [DMARC_FAIL.merge(virus: 'FAIL'), SRS] => 'virus'
      }.freeze

      # Email that an external mailbox forwards: the project from the
      # envelope recipients, and DMARC excused only for a registered
      # forwarder whose SPF check passed.
      def test_automatic_forwarding
        external = ses_message(to: 'support@company.example')
        AUTOMATIC.each do |(verdicts, envelope_from), reason|
          result = admission(external, verdicts: verdicts, envelope_from: envelope_from)

          assert_equal [reason], [result.reason], [verdicts, envelope_from].inspect
          assert_equal 'ecookbook', result.target.project.identifier
        end
      end

      # Headers that name a forwarder decide nothing: the envelope sender
      # comes from the SES event.
      def test_forged_forwarder_headers
        forged = ses_message(headers: { 'Return-Path' => '<support@company.example>',
                                        'X-Forwarded-For' => 'support@company.example',
                                        'Received-SPF' => 'pass (support@company.example)' })

        assert_equal 'dmarc', admission(forged, verdicts: DMARC_FAIL, envelope_from: 'attacker@evil.example').reason
      end

      def test_forwarders_of_another_project_do_not_count
        AwsSesProjectMailSetting.create!(project_id: 2, receive: true)
        result = admission(verdicts: DMARC_FAIL, envelope_from: 'support@company.example',
                           recipients: "onlinestore@#{DOMAIN}")

        assert_equal 'dmarc', result.reason
      end

      def test_a_forward_by_a_member
        @setting.update!(import_forwarded: true)
        result = admission(File.binread(FORWARDED))

        assert_equal 'customer@client.example', result.forward&.sender
        assert_equal User.find(2), result.forwarder
      end

      # Forwards by members, table-driven: each condition alone keeps the
      # message the forwarder's own. The last one is not undone.
      MEMBER_CONDITIONS = %i[setting_off dmarc_not_passed dmarc_allowed_by_the_setting no_permission locked_user
                             unknown_forwarder not_a_member].freeze

      def test_forwards_by_members_that_stay_the_forwarders_own
        MEMBER_CONDITIONS.each do |condition|
          @setting.update!(import_forwarded: true)
          raw, verdicts = send(condition, File.binread(FORWARDED))
          result = admission(raw, verdicts: verdicts, 'import_without_dmarc_pass' => '1')

          assert_equal [nil, nil], [result.forward, result.forwarder], condition
        ensure
          undo_conditions
        end
      end

      def test_the_reasons_that_come_before_the_project
        assert_equal 'no_project', admission(recipients: "nobody@#{DOMAIN}").reason
        assert_equal 'auto_reply', admission(ses_message(headers: { 'Auto-Submitted' => 'auto-replied' })).reason
        assert_equal 'no_verdict', admission(verdicts: nil).reason
      end

      private

      def setting_off(raw)
        @setting.update!(import_forwarded: false)
        [raw, PASS]
      end

      def dmarc_not_passed(raw) = [raw, PASS.merge(dmarc: 'GRAY')]

      def dmarc_allowed_by_the_setting(raw) = [raw, DMARC_FAIL]

      def no_permission(raw)
        Role.find(1).remove_permission!(:add_issues)
        [raw, PASS]
      end

      def locked_user(raw)
        User.find(2).lock!
        [raw, PASS]
      end

      def unknown_forwarder(raw) = [raw.sub('jsmith@somenet.foo', 'stranger@other.example'), PASS]

      # In a private project: Redmine's Non member role may add issues to
      # public ones.
      def not_a_member(raw)
        Member.where(user_id: 2, project_id: 1).destroy_all
        Project.find(1).update!(is_public: false)
        [raw, PASS]
      end

      def undo_conditions
        User.find(2).activate!
        Role.find(1).add_permission!(:add_issues)
      end
    end
  end
end
