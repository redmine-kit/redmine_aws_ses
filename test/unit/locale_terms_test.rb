# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # The Japanese screens use one word for each verdict, as SES's Japanese
    # documentation does: 「失敗」 (認証に失敗) and 「スパム」, never 「未通過」
    # or 「迷惑メール」.
    class LocaleTermsTest < ActiveSupport::TestCase
      def test_the_japanese_terms_of_the_verdicts
        ja = YAML.safe_load_file(File.expand_path('../../config/locales/ja.yml', __dir__))['ja']

        assert_empty(ja.select { |_, text| text.to_s.match?(/未通過|迷惑メール/) })
        assert_equal ['未取得 (DMARC 失敗)', 'DMARC に失敗したメールも取得', 'スパムも取得',
                      '未取得 (別のプロジェクトへの返信)'],
                     ja.values_at('label_aws_ses_mail_reason_dmarc', 'label_aws_ses_mail_import_without_dmarc_pass',
                                  'label_aws_ses_mail_import_spam', 'label_aws_ses_mail_reason_forwarded_reply')
      end
    end
  end
end
