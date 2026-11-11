# frozen_string_literal: true

# The result of importing one received message (docs/admin.md#receiving-email).
# The body is not stored, only where it is in the mail bucket.
class AwsSesReceivedMail < ApplicationRecord
  STATUSES = %w[imported dropped].freeze
  REASONS = %w[no_verdict virus spam dmarc forwarder_spf forwarded_author auto_reply no_project too_large
               import_error].freeze
  KEEP_DAYS = 90

  belongs_to :project, optional: true

  validates :message_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :reason, inclusion: { in: REASONS }, allow_nil: true

  # Deletes the records older than days (Serverless
  # docs/security.md#retention-periods); returns how many.
  def self.prune(days = KEEP_DAYS)
    where(created_at: ...Integer(days).days.ago).delete_all
  end

  def recipient_list
    recipients.to_s.split(/,\s*/)
  end

  # The verdicts of the SES event (RedmineAws::SES::Verdicts::FIELDS).
  def verdicts
    RedmineAws::SES::Verdicts::FIELDS.keys.to_h { |name| [name, self[self.class.verdict_column(name)]] }
                                     .compact.presence
  end

  def verdicts=(values)
    RedmineAws::SES::Verdicts::FIELDS.each_key do |name|
      self[self.class.verdict_column(name)] = values.to_h[name]
    end
  end

  def self.verdict_column(name)
    name == :dmarc_policy ? :dmarc_policy : :"#{name}_verdict"
  end

  # The headers for the record. Anyone can send to the domain, and a header
  # in raw 8-bit text (Shift_JIS without MIME encoding) is not UTF-8, which
  # the database refuses; invalid bytes are replaced as Redmine does. The
  # Date header when it is a date, otherwise the time of the import.
  def describe(mail)
    self.mail_from = self.class.text(Array(mail.from).first)
    self.subject = self.class.text(mail.subject)
    date = mail.date
    self.received_at = date.is_a?(DateTime) ? date : Time.current
  end

  def self.text(value)
    Redmine::CodesetUtil.replace_invalid_utf8(value.to_s).first(255)
  end

  def mark_dropped(reason)
    self.status = 'dropped'
    self.reason = reason
  end

  # result: the issue or the journal that MailHandler created.
  def mark_imported(result)
    self.status = 'imported'
    self.reason = nil
    self.target_type = result.class.name
    self.target_id = result.id
  end

  # Imported, and the issue or the note it created still exists: importing
  # again would create a second one.
  def imported_target?
    status == 'imported' && %w[Issue Journal].include?(target_type) && target_type.constantize.exists?(target_id)
  end

  # Reads the issues of the notes in one query, for a list of records.
  def self.preload_issue_ids(records)
    notes = records.select { |record| record.target_type == 'Journal' }.map(&:target_id)
    issues = Journal.where(id: notes).pluck(:id, :journalized_id).to_h
    records.each do |record|
      record.preloaded_issue_id = record.target_type == 'Journal' ? issues[record.target_id] : record.target_id
    end
  end

  attr_writer :preloaded_issue_id

  # The issue the message created or added a note to.
  def issue_id
    return @preloaded_issue_id if instance_variable_defined?(:@preloaded_issue_id)

    case target_type
    when 'Issue' then target_id
    when 'Journal' then Journal.find_by(id: target_id)&.journalized_id
    end
  end
end
