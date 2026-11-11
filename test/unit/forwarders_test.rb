# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # The registered forwarders of a project (docs/receiving.md#forwarded-email).
    class ForwardersTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper

      # The envelope sender (MAIL FROM) of a registered forwarder: its domain,
      # or its address, also with a +tag (Microsoft 365's SRS, Gmail's
      # forwarding).
      ENVELOPE_SENDERS = {
        'support@company.example' => true, 'SUPPORT@company.example' => true,
        'support+SRS=44ldt=IX=fabrikam.com=bob@company.example' => true,
        'support+caf_=ecookbook=redmine.example.com@company.example' => true,
        'sales@company.example' => false, 'supportx@company.example' => false,
        'support@company.example.evil.example' => false, 'anyone@partner.example' => true,
        'anyone@sub.partner.example' => false, 'partner.example' => false, '' => false, nil => false
      }.freeze

      def test_registered_forwarders
        setting = AwsSesProjectMailSetting.new(project: Project.find(1),
                                               forwarders: "Support@Company.example\n\n  partner.example  \n")
        ENVELOPE_SENDERS.each do |envelope_from, expected|
          assert_equal expected, setting.forwarder?(envelope_from), envelope_from.inspect
        end
        assert_equal %w[support@company.example partner.example], setting.forwarder_list
      end

      def test_forwarders_must_be_addresses_or_domains
        { "support@company.example\npartner.example" => true, 'a b@company.example' => false,
          'company' => false, '@company.example' => false, 'support@' => false, 'http://company.example' => false,
          (1..21).map { |i| "f#{i}.example" }.join("\n") => false }.each do |forwarders, valid|
          setting = AwsSesProjectMailSetting.new(project: Project.find(1), forwarders: forwarders)

          assert_equal valid, setting.valid?, forwarders
          assert_includes setting.errors.full_messages.join, 'Forwarders' unless valid
        end
      end
    end
  end
end
