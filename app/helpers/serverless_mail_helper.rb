# frozen_string_literal: true

module ServerlessMailHelper
  # An SES value (HEALTHY, SUCCESS, BOUNCE...) in the terms of the SES
  # console (docs/admin.md#terms); the value itself when it has no term.
  def serverless_mail_value(kind, value)
    return '-' if value.blank?

    l(:"label_serverless_mail_#{kind}_#{value.to_s.downcase}", default: value.to_s)
  end

  # "Virus PASS, Spam PASS, DMARC FAIL": SES leaves the verdicts in English.
  def serverless_mail_verdicts(verdicts)
    verdicts.to_h.slice(:virus, :spam, :dmarc).map do |name, verdict|
      label = name == :dmarc ? 'DMARC' : l(:"label_serverless_mail_verdict_#{name}")
      "#{label} #{verdict}"
    end.join(', ')
  end
end
