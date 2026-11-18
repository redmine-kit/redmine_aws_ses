# frozen_string_literal: true

require_relative '../test_helper'

module RedmineKit
  module Aws
    module Ses
      class VerdictsTest < ActiveSupport::TestCase
        include RedmineKit::Aws::Ses::TestHelper

        def reason(settings = RedmineKit::Aws::Ses::DEFAULTS, **changes)
          RedmineKit::Aws::Ses::Verdicts.reason(PASS.merge(changes), settings)
        end

        def excused(**changes)
          RedmineKit::Aws::Ses::Verdicts.reason(PASS.merge(dmarc: 'FAIL', **changes), allowing, dmarc_excused: true)
        end

        def allowing(dmarc: '0', spam: '0')
          RedmineKit::Aws::Ses::DEFAULTS.merge('import_without_dmarc_pass' => dmarc, 'import_spam' => spam)
        end

        def test_a_message_that_passes
          assert_nil reason
          assert_nil reason(spf: 'FAIL', dkim: 'GRAY')
        end

        def test_virus_spam_and_dmarc
          assert_equal 'virus', reason(virus: 'FAIL')
          assert_equal 'spam', reason(spam: 'GRAY')
          assert_equal 'dmarc', reason(dmarc: 'FAIL')
          assert_equal 'dmarc', reason(dmarc: 'PROCESSING_FAILED')
        end

        def test_each_combination_of_the_settings
          { allowing => [nil, 'spam', 'dmarc'],
            allowing(dmarc: '1') => [nil, 'spam', nil],
            allowing(spam: '1') => [nil, nil, 'dmarc'],
            allowing(dmarc: '1', spam: '1') => [nil, nil, nil] }.each do |settings, expected|
            actual = [reason(settings), reason(settings, spam: 'FAIL'), reason(settings, dmarc: 'FAIL')]

            assert_equal expected, actual, settings.inspect
            assert_equal 'virus', reason(settings, virus: 'FAIL'), 'a virus is never imported'
          end
        end

        # A registered forwarder excuses DMARC only (Admission#via_forwarder?).
        def test_dmarc_excused_for_a_forwarder
          assert_nil excused
          assert_equal 'spam', excused(spam: 'FAIL')
          assert_equal 'virus', excused(virus: 'FAIL')
        end

        def test_missing_spam_or_dmarc_verdicts_count_as_not_passing
          assert_equal 'spam', RedmineKit::Aws::Ses::Verdicts.reason({ virus: 'PASS', dmarc: 'PASS' }, allowing)
          assert_nil RedmineKit::Aws::Ses::Verdicts.reason({ virus: 'PASS' }, allowing(dmarc: '1', spam: '1'))
        end

        def test_without_verdicts
          assert_equal 'no_verdict', RedmineKit::Aws::Ses::Verdicts.reason(nil)
          assert_equal 'no_verdict', RedmineKit::Aws::Ses::Verdicts.reason({ spam: 'PASS', dmarc: 'PASS' })
        end

        def test_from_the_task_variables
          env = { 'SES_SPAM_VERDICT' => 'pass', 'SES_VIRUS_VERDICT' => 'PASS', 'SES_DMARC_VERDICT' => 'FAIL',
                  'SES_DMARC_POLICY' => 'reject' }

          assert_equal({ spam: 'PASS', virus: 'PASS', dmarc: 'FAIL', dmarc_policy: 'REJECT' },
                       RedmineKit::Aws::Ses::Verdicts.from_env(env))
          assert_nil RedmineKit::Aws::Ses::Verdicts.from_env({})
        end
      end
    end
  end
end
