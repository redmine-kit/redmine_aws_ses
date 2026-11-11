# frozen_string_literal: true

# The result of importing one received message (docs/admin.md#receiving-email).
# The body is not stored, only where it is in the mail bucket.
class AwsSesReceivedMail < ApplicationRecord
  STATUSES = %w[imported dropped].freeze
  REASONS = %w[no_verdict virus spam dmarc auto_reply no_project import_error].freeze
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

  # The issue the message created or added a note to.
  def issue_id
    case target_type
    when 'Issue' then target_id
    when 'Journal' then Journal.find_by(id: target_id)&.journalized_id
    end
  end
end
