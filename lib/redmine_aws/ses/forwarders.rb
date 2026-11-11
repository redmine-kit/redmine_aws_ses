# frozen_string_literal: true

module RedmineAws
  module SES
    # The registered forwarders of a project (AwsSesProjectMailSetting#forwarders,
    # docs/receiving.md#forwarded-email): domains, or addresses, one per line.
    class Forwarders
      # A domain, or an address (its part before @ as Redmine's MailHandler
      # accepts it).
      DOMAIN = /\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/
      LOCAL = %r{\A[a-z0-9!#$%&'*+/=?^_`{|}~.-]{1,64}\z}
      MAX = 20

      attr_reader :list

      def initialize(text)
        @list = text.to_s.split(/[\r\n]+/).map { |line| line.strip.downcase }.compact_blank.uniq
      end

      # Whether an envelope sender (SES's mail.source) is a forwarder's: the
      # forwarder's domain, or its address, also with a +tag (Microsoft 365's
      # SRS writes <address>+SRS=...@<domain>).
      def include?(envelope_from)
        local, _, domain = envelope_from.to_s.downcase.rpartition('@')
        return false if local.empty? || domain.empty?

        list.any? do |entry|
          entry_local, _, entry_domain = entry.rpartition('@')
          domain == entry_domain && (entry_local.empty? || local == entry_local || local.start_with?("#{entry_local}+"))
        end
      end

      def too_many?
        list.size > MAX
      end

      def valid?
        list.all? do |entry|
          local, at, domain = entry.rpartition('@')
          DOMAIN.match?(domain) && (at.empty? || LOCAL.match?(local))
        end
      end
    end
  end
end
