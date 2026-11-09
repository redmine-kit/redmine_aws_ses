# frozen_string_literal: true

# A project's email settings (docs/admin.md#project-email-settings): whether
# it receives email, its alias, and the values of the issues it creates.
class ServerlessProjectMailSetting < ApplicationRecord
  include Redmine::SafeAttributes

  UNKNOWN_USER = %w[ignore accept create].freeze
  RESERVED = %w[postmaster abuse hostmaster webmaster mailer-daemon root admin administrator noreply no-reply
                security].freeze
  LOCAL_PART = /\A[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?\z/

  belongs_to :project
  belongs_to :tracker, optional: true
  belongs_to :category, class_name: 'IssueCategory', optional: true
  belongs_to :priority, class_name: 'IssuePriority', optional: true
  belongs_to :assigned_to, class_name: 'Principal', optional: true

  safe_attributes 'receive', 'alias_name', 'tracker_id', 'category_id', 'priority_id', 'assigned_to_id',
                  'is_private', 'unknown_user'

  normalizes :alias_name, with: ->(value) { value.to_s.strip.downcase.presence }

  validates :unknown_user, inclusion: { in: UNKNOWN_USER }
  validates :alias_name, format: { with: LOCAL_PART }, allow_nil: true
  validate :alias_is_free

  # The setting of the project that receives email at this part before @
  # (its identifier or its alias).
  def self.receiving_for(local)
    by_alias = where(receive: true).find_by(alias_name: local)
    return by_alias if by_alias

    project = Project.active.find_by(identifier: local)
    project && where(receive: true).find_by(project: project)
  end

  # The project's address: the alias, or the identifier when it fits before @.
  def self.address_for(project, setting = find_by(project: project))
    domain = RedmineServerlessSes.domain
    local = setting&.alias_name.presence || project.identifier
    domain && local.length <= 64 ? "#{local}@#{domain}" : nil
  end

  def address
    self.class.address_for(project, self)
  end

  # Default values of the issues the project creates from email, as
  # MailHandler's options take them (names, not IDs).
  def issue_defaults
    { tracker: tracker&.name, category: category&.name, priority: priority&.name,
      assigned_to: assigned_to.is_a?(User) ? assigned_to.login : assigned_to&.name,
      is_private: is_private? ? '1' : nil }.compact
  end

  private

  def alias_is_free
    return if alias_name.blank?

    taken = RESERVED.include?(alias_name) || alias_name == RedmineServerlessSes.global_local_part ||
            Project.where.not(id: project_id).exists?(identifier: alias_name) ||
            self.class.where.not(project_id: project_id).exists?(alias_name: alias_name)
    errors.add(:alias_name, :taken) if taken
  end
end
