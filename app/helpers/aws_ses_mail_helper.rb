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

  # The SES account as the "Email sending" tab shows it (aws_admin/values of
  # redmine_aws, as Administration › Information shows values).
  def aws_ses_mail_account_rows(account)
    sending = :"label_aws_ses_mail_sending_status_#{account['sending_enabled'] ? 'enabled' : 'paused'}"
    [{ name: l(:label_aws_ses_mail_enforcement_status),
       value: aws_ses_mail_value(:enforcement_status, account['enforcement_status']) },
     { name: l(:label_aws_ses_mail_sending_enabled), value: l(sending) },
     { name: l(:label_aws_ses_mail_production_access), value: format_object(account['production_access']) }] +
      aws_ses_mail_quota_rows(account)
  end

  def aws_ses_mail_quota_rows(account)
    rate = number_with_delimiter(account['max_send_rate'].to_f.round(2).to_s.sub(/\.0\z/, ''))
    [{ name: l(:label_aws_ses_mail_quota), value: number_with_delimiter(account['max_24_hour_send'].to_i) },
     { name: l(:label_aws_ses_mail_sent_last_24_hours),
       value: number_with_delimiter(account['sent_last_24_hours'].to_i) },
     { name: l(:label_aws_ses_mail_rate), value: l(:text_aws_ses_mail_rate_value, count: rate) }]
  end

  def aws_ses_mail_identity_rows(domain, identity)
    [{ name: l(:label_aws_ses_mail_domain), value: domain },
     { name: l(:label_aws_ses_mail_verified), value: format_object(identity['verified']) },
     { name: 'DKIM', value: aws_ses_mail_value(:dkim_status, identity['dkim_status']) }]
  end

  # The addresses of the "Email receiving" tab.
  def aws_ses_mail_address_rows(domain, snapshot)
    [{ name: l(:label_aws_ses_mail_domain), value: domain },
     { name: l(:label_aws_ses_mail_global_address), value: RedmineAws::SES.global_address },
     { name: 'MX', value: aws_ses_mail_mx(snapshot) }]
  end

  # The MX hosts as the last refresh read them; "Unknown" when they could
  # not be read, or before the first refresh.
  def aws_ses_mail_mx(snapshot)
    mx = snapshot&.section(:mx)
    return l(:text_aws_ses_mail_mx_unknown) if mx.nil?

    mx.empty? ? l(:label_none) : mx.join(', ')
  end

  # Warnings about the addresses of projects that receive email: role
  # addresses (allowed, as a project may receive support@ on purpose) and
  # the default address, which takes the email sent to it.
  def aws_ses_mail_address_warnings(settings)
    receiving = settings.select { |setting| setting.receive? && setting.address }
    { text_aws_ses_mail_role_addresses: :role_address?,
      text_aws_ses_mail_default_address_taken: :default_address? }.filter_map do |key, check|
      addresses = receiving.select(&check).map(&:address)
      l(key, addresses: addresses.join(', ')) if addresses.any?
    end
  end
end
