# frozen_string_literal: true

# A project's email settings (docs/admin.md#project-email-settings): whether
# it receives email and the values of the issues it creates. The project's
# address is its identifier before @.
class AwsSesProjectMailSetting < ApplicationRecord
  include Redmine::SafeAttributes

  UNKNOWN_USER = %w[ignore accept create].freeze
  # Role addresses (RFC 2142 and common ones) that never go to a project, even
  # when a project has such an identifier.
  RESERVED = %w[postmaster abuse hostmaster webmaster mailer-daemon root admin administrator noreply no-reply
                security].freeze
  LOCAL_PART = /\A[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?\z/

  belongs_to :project
  belongs_to :tracker, optional: true
  belongs_to :category, class_name: 'IssueCategory', optional: true
  belongs_to :priority, class_name: 'IssuePriority', optional: true
  belongs_to :assigned_to, class_name: 'Principal', optional: true

  safe_attributes 'receive', 'tracker_id', 'category_id', 'priority_id', 'assigned_to_id', 'is_private',
                  'unknown_user'

  validates :unknown_user, inclusion: { in: UNKNOWN_USER }
  validate :validate_choices, :validate_unknown_user

  # The setting of the project that receives email at this part before @.
  def self.receiving_for(local)
    return unless addressable?(local)

    project = Project.active.find_by(identifier: local)
    project && where(receive: true).find_by(project: project)
  end

  # The project's address, or nil when its identifier cannot be one.
  def self.address_for(project)
    domain = RedmineAws::SES.domain
    domain && addressable?(project.identifier) ? "#{project.identifier}@#{domain}" : nil
  end

  # An identifier can be an address when it fits before @ (64 characters),
  # is not a role address and is not the default address.
  def self.addressable?(identifier)
    identifier.to_s.length.between?(1, 64) && RESERVED.exclude?(identifier) &&
      identifier != RedmineAws::SES.global_local_part
  end

  # Keeps the user for the validation of unknown_user, as Redmine's
  # Issue#safe_attributes= keeps it for its own checks.
  def safe_attributes=(attrs, user = User.current)
    @attributes_set_by = user
    super
  end

  def address
    self.class.address_for(project)
  end

  # The choices of the form, which the validation checks too: the values an
  # issue of the project can take.
  def trackers
    project.trackers
  end

  def categories
    project.issue_categories
  end

  def priorities
    IssuePriority.active
  end

  def assignees
    project.assignable_users
  end

  # The unknown_user values the user may choose. With "create", MailHandler
  # creates an active user for every unknown sender, and only administrators
  # create users in Redmine; a value already saved stays as it is.
  def unknown_user_values(user = User.current)
    user.admin? || unknown_user_in_database == 'create' ? UNKNOWN_USER : UNKNOWN_USER - %w[create]
  end

  # Default values of the issues the project creates from email, as
  # MailHandler's options take them (names, not IDs).
  def issue_defaults
    { tracker: tracker&.name, category: category&.name, priority: priority&.name,
      assigned_to: assigned_to.is_a?(User) ? assigned_to.login : assigned_to&.name,
      is_private: is_private? ? '1' : nil }.compact
  end

  private

  # A value that changes must be one of the choices. A value saved earlier
  # that is no longer one (a tracker removed from the project) does not stop
  # other changes: MailHandler checks it again on import.
  def validate_choices
    { tracker: trackers, category: categories, priority: priorities, assigned_to: assignees }.each do |name, choices|
      attribute = :"#{name}_id"
      id = self[attribute]
      next if id.nil? || !attribute_changed?(attribute)

      errors.add(attribute, :inclusion) unless choices.exists?(id)
    end
  end

  # Checked when a user sets the values (safe_attributes=).
  def validate_unknown_user
    return unless @attributes_set_by && unknown_user_changed?

    errors.add(:unknown_user, :inclusion) if unknown_user_values(@attributes_set_by).exclude?(unknown_user)
  end
end
