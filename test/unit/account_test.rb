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

      def test_a_failing_check
        stub_ses(get_account: 'AccessDeniedException')
        result = RedmineAws::Admin.run_checks.find { |r| r.name == 'ses' }

        assert_not result.ok
        assert_match(/AccessDeniedException/, result.detail)
      end
    end
  end
end
