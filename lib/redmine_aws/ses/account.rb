# frozen_string_literal: true

require 'resolv'

module RedmineAws
  module SES
    # Reads the state of SES and DNS for the email tabs (docs/admin.md): the
    # account, the domain's identity, the suppression list and the domain's MX
    # records. The rake task redmine_aws_ses:refresh (on a schedule) and the
    # tabs' Refresh link store it in AwsSesSnapshot; the tabs show what is
    # stored and never call SES or DNS themselves.
    class Account
      SUPPRESSED_LIMIT = 100
      MX_TIMEOUT = 2
      SECTIONS = %w[account identity suppressed mx].freeze

      def initialize(client: Clients.ses, domain: RedmineAws::SES.domain)
        @client = client
        @domain = domain
      end

      # The state as plain values (JSON), each section read on its own. A
      # section that fails is nil, with the error's class in 'errors' (the
      # tabs show the class only); the message goes to the log. Any
      # StandardError, as redmine_aws's connection checks do: SES and DNS fail
      # with service, network, credential or region errors, which have no
      # common class.
      def state
        SECTIONS.each_with_object({ 'domain' => @domain, 'errors' => {} }) do |section, data|
          data[section] = public_send(section)
        rescue StandardError => e
          Rails.logger.error "[redmine_aws_ses] could not read the #{section} section: #{e.class}: #{e.message}"
          data['errors'][section] = e.class.name
        end
      end

      def account
        a = @client.get_account
        quota = a.send_quota
        { 'production_access' => a.production_access_enabled, 'sending_enabled' => a.sending_enabled,
          'enforcement_status' => a.enforcement_status, 'max_24_hour_send' => quota&.max_24_hour_send,
          'max_send_rate' => quota&.max_send_rate, 'sent_last_24_hours' => quota&.sent_last_24_hours }
      end

      def identity
        return unless @domain

        i = @client.get_email_identity(email_identity: @domain)
        { 'verified' => i.verified_for_sending_status, 'dkim_status' => i.dkim_attributes&.status }
      end

      # Addresses on the account's suppression list. The tab matches them with
      # Redmine's users when it shows them (AwsSesSnapshot#suppressed).
      def suppressed
        @client.list_suppressed_destinations(page_size: SUPPRESSED_LIMIT).suppressed_destination_summaries.map do |d|
          { 'address' => d.email_address, 'reason' => d.reason, 'last_update' => d.last_update_time&.iso8601 }
        end
      end

      # The MX hosts of Redmine's domain, from DNS.
      def mx
        return unless @domain

        Resolv::DNS.open do |dns|
          dns.timeouts = MX_TIMEOUT
          dns.getresources(@domain, Resolv::DNS::Resource::IN::MX).map { |mx| mx.exchange.to_s.downcase }.sort
        end
      end

      def unsuppress(address)
        @client.delete_suppressed_destination(email_address: address)
      end

      # The connection check of redmine_aws's Status tab.
      def check
        a = @client.get_account
        sending = ::I18n.t(:"label_aws_ses_mail_sending_status_#{a.sending_enabled ? 'enabled' : 'paused'}")
        production = ::I18n.t(a.production_access_enabled ? :general_text_Yes : :general_text_No)
        ::I18n.t(:text_aws_ses_mail_sending_check, sending: sending, production: production)
      end
    end
  end
end
