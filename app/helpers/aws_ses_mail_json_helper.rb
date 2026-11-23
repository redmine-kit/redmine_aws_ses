# frozen_string_literal: true

# The email tabs and the project's Email tab as the new UI's JSON, formatted
# as Redmine's pages format them (AwsSesMailHelper's rows and values), from the
# controllers' instance variables.
module AwsSesMailJsonHelper
  # GET admin/aws/mail_sending.json (@domain, @snapshot): when the state was
  # read, the account, the sender domain and the suppression list, each with
  # its rows or the error of reading it, and whether the jobs' page of Redmine
  # Kit AWS SQS is there (the failed email's link).
  def aws_ses_mail_sending_json
    { updated: aws_ses_mail_updated, domain: @domain,
      account: aws_ses_mail_section_json(:account) { aws_ses_mail_account_json },
      identity: aws_ses_mail_section_json(:identity) { aws_ses_mail_identity_json },
      suppressed: aws_ses_mail_section_json(:suppressed) { aws_ses_mail_suppressed_list },
      failed_jobs: respond_to?(:aws_sqs_jobs_path) }
  end

  def aws_ses_mail_updated
    @snapshot && format_time(@snapshot.fetched_at)
  end

  # A section of the state: { rows } (nil before the first refresh), or
  # { error } as the page says it.
  def aws_ses_mail_section_json(name)
    error = @snapshot&.error(name)
    return { error: l(:text_aws_ses_mail_api_error, error: error) } if error

    { rows: yield }
  end

  def aws_ses_mail_account_json
    account = @snapshot&.section(:account)
    account && aws_ses_mail_account_rows(account)
  end

  def aws_ses_mail_identity_json
    identity = @snapshot&.section(:identity)
    identity && @domain && aws_ses_mail_identity_rows(@domain, identity)
  end

  def aws_ses_mail_suppressed_list
    @snapshot&.suppressed.to_a.map do |destination|
      { address: destination[:address], user: destination[:user].to_s.presence,
        reason: aws_ses_mail_value(:suppression_reason, destination[:reason]),
        last_update: destination[:last_update] ? format_time(destination[:last_update]) : '' }
    end
  end

  # GET admin/aws/mail_receiving.json (@settings, @domain, @snapshot,
  # @project_settings, @received): the addresses, the warnings the page shows,
  # the projects' addresses, the received email, and the settings with the
  # choices of the form.
  def aws_ses_mail_receiving_json
    { updated: aws_ses_mail_updated, domain: @domain,
      addresses: @domain && aws_ses_mail_address_rows(@domain, @snapshot),
      warnings: aws_ses_mail_receiving_warnings, projects: aws_ses_mail_projects_json,
      bucket: RedmineKit::Aws::Ses.mail_bucket.present?,
      received: @received.map { |mail| aws_ses_mail_received_json(mail) } }.merge(aws_ses_mail_settings_json)
  end

  # The receiving settings and the choices of their form.
  def aws_ses_mail_settings_json
    ses = RedmineKit::Aws::Ses
    { settings: @settings.slice(*ses::DEFAULTS.keys),
      global_mail: ses::GLOBAL_MAIL.map { |v| { value: v, label: l(:"label_aws_ses_mail_global_#{v}") } },
      default_projects: Project.active.sorted.map { |p| { value: p.identifier, label: p.name } } }
  end

  # The warnings under the addresses, as the page shows them (with a domain).
  def aws_ses_mail_receiving_warnings
    return [] unless @domain

    ses = RedmineKit::Aws::Ses
    warnings = []
    if ses.global_local_parts.size > 1
      warnings << l(:text_aws_ses_mail_emission_address, address: "#{ses.emission_local_part}@#{@domain}")
    end
    warnings.concat(aws_ses_mail_address_warnings(@project_settings)) if aws_ses_mail_projects_listed?
    warnings
  end

  def aws_ses_mail_projects_listed?
    @domain && RedmineKit::Aws::Ses.per_project_addresses? && @project_settings.any?
  end

  # The projects' addresses, when the page lists them; nil otherwise.
  def aws_ses_mail_projects_json
    return unless aws_ses_mail_projects_listed?

    @project_settings.map do |setting|
      { project: aws_ses_mail_project_ref(setting.project), address: setting.address || '-', receive: setting.receive? }
    end
  end

  def aws_ses_mail_project_ref(project)
    project && { identifier: project.identifier, name: project.name }
  end

  # A received email's row: its time, sender, subject, project, verdicts and
  # result (the issue it made, Imported, or why it was dropped).
  def aws_ses_mail_received_json(mail)
    imported = mail.status == 'imported'
    { id: mail.id, status: mail.status, received_at: format_time(mail.received_at || mail.created_at),
      from: mail.mail_from, subject: mail.subject, project: aws_ses_mail_project_ref(mail.project),
      verdicts: aws_ses_mail_verdicts(mail.verdicts), result: aws_ses_mail_result(mail),
      issue_id: imported ? mail.issue_id : nil }
  end

  def aws_ses_mail_result(mail)
    return l(:"label_aws_ses_mail_reason_#{mail.reason}") if mail.status != 'imported'

    mail.issue_id ? "##{mail.issue_id}" : l(:label_aws_ses_mail_imported)
  end

  # GET projects/:id/aws_ses_mail_setting.json: the address, the values, the
  # choices the form offers (the values an issue of the project can take) and
  # which values the user may change (the safe attributes: forwarded email is
  # an administrator's).
  def aws_ses_project_mail_json(setting)
    { address: setting.address, values: aws_ses_project_mail_values(setting),
      editable: setting.safe_attribute_names }.merge(aws_ses_project_mail_choices(setting))
  end

  def aws_ses_project_mail_values(setting)
    names = AwsSesProjectMailSetting.safe_attributes.flat_map(&:first)
    setting.attributes.slice(*names).transform_values { |value| value.nil? ? '' : value.to_s }
  end

  # The values an issue of the project can take, as the form's choices.
  def aws_ses_project_mail_choices(setting)
    choices = ->(records) { records.map { |record| { value: record.id.to_s, label: record.to_s } } }
    { trackers: choices.call(setting.trackers), categories: choices.call(setting.categories),
      priorities: choices.call(setting.priorities), assignees: choices.call(setting.assignees) }
      .merge(aws_ses_project_mail_labelled_choices(setting))
  end

  def aws_ses_project_mail_labelled_choices(setting)
    labelled = ->(values, prefix) { values.map { |value| { value: value, label: l(:"#{prefix}_#{value}") } } }
    { unknown_user: labelled.call(setting.unknown_user_values, 'label_aws_ses_mail_unknown_user'),
      forwarded_author: labelled.call(AwsSesProjectMailSetting::FORWARDED_AUTHORS,
                                      'label_aws_ses_mail_forwarded_author') }
  end
end
