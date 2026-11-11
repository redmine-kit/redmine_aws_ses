# frozen_string_literal: true

# The state of SES and DNS that the email tabs show (RedmineAws::SES::Account),
# as read by the last refresh: the rake task redmine_aws_ses:refresh, on a
# schedule, or the tabs' Refresh link. Only the latest is kept.
class AwsSesSnapshot < ApplicationRecord
  DOMAIN_SECTIONS = %w[identity mx].freeze

  serialize :data, coder: JSON

  def self.latest
    order(fetched_at: :desc, id: :desc).first
  end

  # Reads the state and keeps it in place of the older snapshots.
  def self.refresh!(account = RedmineAws::SES::Account.new)
    snapshot = create!(data: account.state, fetched_at: Time.current)
    where(fetched_at: ..snapshot.fetched_at).where.not(id: snapshot.id).delete_all
    snapshot
  end

  # A section (account, identity, suppressed, mx) for the domain of Redmine
  # now; nil when it failed, or when it was read for another domain
  # (Setting.mail_from changed since).
  def section(name, domain = RedmineAws::SES.domain)
    data[name.to_s] if current?(name, domain)
  end

  # The class of the error a section failed with, on the same terms.
  def error(name, domain = RedmineAws::SES.domain)
    data.dig('errors', name.to_s) if current?(name, domain)
  end

  # The suppression list with the names of the Redmine users who have the
  # addresses, matched without case as Redmine's User.having_mail does.
  def suppressed
    list = Array(data['suppressed'])
    users = user_names(list.map { |d| d['address'].to_s.downcase })
    list.map { |destination| suppressed_row(destination, users) }
  end

  # After an address is removed from the suppression list, until the next
  # refresh.
  def remove_suppressed!(address)
    list = Array(data['suppressed']).reject { |d| d['address'].to_s.casecmp?(address) }
    update!(data: data.merge('suppressed' => list))
  end

  private

  def suppressed_row(destination, users)
    address = destination['address'].to_s
    { address: address, reason: destination['reason'], user: users[address.downcase],
      last_update: destination['last_update'] && Time.zone.parse(destination['last_update']) }
  end

  # The sections of the domain are read for the domain of the time.
  def current?(name, domain)
    DOMAIN_SECTIONS.exclude?(name.to_s) || data['domain'] == domain
  end

  def user_names(addresses)
    EmailAddress.where("LOWER(#{EmailAddress.table_name}.address) IN (?)", addresses).includes(:user)
                .to_h { |e| [e.address.downcase, e.user&.name] }
  end
end
