# frozen_string_literal: true

module AwsSesMailHelper
  # An SES value (HEALTHY, SUCCESS, BOUNCE...) in the terms of the SES
  # console (docs/admin.md#terms); the value itself when it has no term.
  def aws_ses_mail_value(kind, value)
    return '-' if value.blank?

    l(:"label_aws_ses_mail_#{kind}_#{value.to_s.downcase}", default: value.to_s)
  end

  # The verdicts that did not pass, as short labels ("Spam, DMARC fail"), or
  # "Passed"; terms from SES's descriptions of the verdicts
  # (docs/admin.md#terms). An unknown value counts as a failure.
  def aws_ses_mail_verdicts(verdicts)
    verdicts = verdicts.to_h.slice(:virus, :spam, :dmarc)
    return '-' if verdicts.empty?

    labels = verdicts.reject { |_, verdict| verdict == 'PASS' }.map do |name, verdict|
      value = %w[GRAY PROCESSING_FAILED].include?(verdict) ? verdict.downcase : 'fail'
      l(:"label_aws_ses_mail_verdict_#{name}_#{value}")
    end
    labels.empty? ? l(:label_aws_ses_mail_verdicts_passed) : labels.join(', ')
  end
end
