# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # The SES state and the connection check, with SDK response stubs: neither
    # LocalStack nor moto has SES v2 GetAccount.
    class AccountTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper

      def test_the_connection_check
        stub_ses(get_account: { production_access_enabled: true, sending_enabled: true })
        result = RedmineAws::Admin.run_checks.find { |r| r.name == 'ses' }

        assert result.ok, result.detail
        assert_equal 'Sending: Enabled, production access: Yes', result.detail
      end

      def test_the_state
        state = read_state

        assert_equal [DOMAIN, {}], state.values_at('domain', 'errors')
        assert_equal 'HEALTHY', state.dig('account', 'enforcement_status')
        assert_equal 'SUCCESS', state.dig('identity', 'dkim_status')
        assert_equal %w[jsmith@somenet.foo BOUNCE], state['suppressed'].first.values_at('address', 'reason')
        assert_equal ['inbound-smtp.example'], state['mx']
      end

      def test_the_state_is_plain_values
        state = read_state

        assert_equal state, JSON.parse(state.to_json), 'as the snapshot keeps them'
      end

      # A section that fails keeps only the class of the error; the others are
      # read.
      def test_sections_fail_on_their_own
        Resolv::DNS.any_instance.stubs(:getresources).raises(Resolv::ResolvError, 'no answer from 10.0.0.2')
        stub_ses(get_account: 'AccessDeniedException',
                 list_suppressed_destinations: { suppressed_destination_summaries: [] })
        state = nil
        log = capture_log { state = with_ses_settings { RedmineAws::SES::Account.new.state } }

        assert_equal({ 'account' => 'Aws::SESV2::Errors::AccessDeniedException', 'mx' => 'Resolv::ResolvError' },
                     state['errors'])
        assert_nil state['account']
        assert_equal [], state['suppressed']
        assert_match(/could not read the mx section: Resolv::ResolvError: no answer from 10\.0\.0\.2/, log)
      end

      def test_only_the_latest_snapshot_is_kept
        first = refresh
        second = refresh

        assert_equal [second], AwsSesSnapshot.all.to_a
        assert_not AwsSesSnapshot.exists?(first.id)
      end

      # The sections of the domain are those of the domain they were read for.
      def test_the_sections_of_another_domain
        snapshot = refresh
        with_ses_settings { assert_equal [[], true], [snapshot.section(:mx), snapshot.section(:identity)['verified']] }
        with_settings(mail_from: 'redmine@other.example') do
          assert_equal [nil, nil], [snapshot.section(:mx), snapshot.section(:identity)]
          assert_equal 'HEALTHY', snapshot.section(:account)['enforcement_status']
        end
      end

      def test_a_failing_check
        stub_ses(get_account: 'AccessDeniedException')
        result = RedmineAws::Admin.run_checks.find { |r| r.name == 'ses' }

        assert_not result.ok
        assert_match(/AccessDeniedException/, result.detail)
      end

      private

      def read_state
        Resolv::DNS.any_instance.stubs(:getresources).returns([stub(exchange: 'Inbound-SMTP.example')])
        stub_ses_state
        with_ses_settings { RedmineAws::SES::Account.new.state }
      end

      def refresh
        stub_ses_state
        Resolv::DNS.any_instance.stubs(:getresources).returns([])
        with_ses_settings { AwsSesSnapshot.refresh! }
      end
    end
  end
end
