# frozen_string_literal: true

module RedmineAws
  module SES
    # The state of SES for the "Sending email" page, cached for a minute.
    class Account
      CACHE_SECONDS = 60
      SUPPRESSED_LIMIT = 100

      def initialize(client: Clients.ses)
        @client = client
      end

      def account
        cached(:account) do
          a = @client.get_account
          { production_access: a.production_access_enabled, sending_enabled: a.sending_enabled,
            enforcement_status: a.enforcement_status, max_24_hour_send: a.send_quota&.max_24_hour_send,
            max_send_rate: a.send_quota&.max_send_rate, sent_last_24_hours: a.send_quota&.sent_last_24_hours }
        end
      end

      def identity(domain)
        cached(:identity, domain) do
          i = @client.get_email_identity(email_identity: domain)
          { verified: i.verified_for_sending_status, dkim_status: i.dkim_attributes&.status }
        end
      end

      # Addresses on the account's suppression list, with the Redmine users
      # who have them, matched without case as Redmine's User.having_mail does.
      def suppressed
        cached(:suppressed) do
          list = @client.list_suppressed_destinations(page_size: SUPPRESSED_LIMIT).suppressed_destination_summaries
          addresses = list.map { |d| d.email_address.downcase }
          users = EmailAddress.where("LOWER(#{EmailAddress.table_name}.address) IN (?)", addresses).includes(:user)
                              .to_h { |e| [e.address.downcase, e.user&.name] }
          list.map do |d|
            { address: d.email_address, reason: d.reason, last_update: d.last_update_time,
              user: users[d.email_address.downcase] }
          end
        end
      end

      def unsuppress(address)
        @client.delete_suppressed_destination(email_address: address)
        Rails.cache.delete(cache_key(:suppressed))
      end

      def check
        a = @client.get_account
        sending = ::I18n.t(:"label_aws_ses_mail_sending_status_#{a.sending_enabled ? 'enabled' : 'paused'}")
        production = ::I18n.t(a.production_access_enabled ? :general_text_Yes : :general_text_No)
        ::I18n.t(:text_aws_ses_mail_sending_check, sending: sending, production: production)
      end

      private

      def cached(*key, &)
        Rails.cache.fetch(cache_key(*key), expires_in: CACHE_SECONDS, &)
      end

      def cache_key(*key)
        ['redmine_aws_ses', *key]
      end
    end
  end
end
