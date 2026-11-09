# frozen_string_literal: true

require_relative '../test_helper'

module RedmineServerlessSes
  class VerdictsTest < ActiveSupport::TestCase
    include RedmineServerlessSes::TestHelper

    def reason(settings = RedmineServerlessSes::DEFAULTS, **changes)
      RedmineServerlessSes::Verdicts.reason(PASS.merge(changes), settings)
    end

    def allowing(dmarc: '0', spam: '0')
      RedmineServerlessSes::DEFAULTS.merge('import_without_dmarc_pass' => dmarc, 'import_spam' => spam)
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

    def test_missing_spam_or_dmarc_verdicts_count_as_not_passing
      assert_equal 'spam', RedmineServerlessSes::Verdicts.reason({ virus: 'PASS', dmarc: 'PASS' }, allowing)
      assert_nil RedmineServerlessSes::Verdicts.reason({ virus: 'PASS' }, allowing(dmarc: '1', spam: '1'))
    end

    def test_without_verdicts
      assert_equal 'no_verdict', RedmineServerlessSes::Verdicts.reason(nil)
      assert_equal 'no_verdict', RedmineServerlessSes::Verdicts.reason({ spam: 'PASS', dmarc: 'PASS' })
    end

    def test_from_the_task_variables
      env = { 'SES_SPAM_VERDICT' => 'pass', 'SES_VIRUS_VERDICT' => 'PASS', 'SES_DMARC_VERDICT' => 'FAIL',
              'SES_DMARC_POLICY' => 'reject' }

      assert_equal({ spam: 'PASS', virus: 'PASS', dmarc: 'FAIL', dmarc_policy: 'REJECT' },
                   RedmineServerlessSes::Verdicts.from_env(env))
      assert_nil RedmineServerlessSes::Verdicts.from_env({})
    end
  end
end
