# frozen_string_literal: true

# Redmine's email through Amazon SES (docs/README.md): retries of sending by
# error type, importing email that SES received, and addresses per project.
module RedmineServerlessSes
  VERSION = '0.2.0'

  DEFAULTS = {
    'global_local_part' => 'noreply',
    'global_mail' => 'drop',
    'default_project' => '',
    'per_project_addresses' => '0',
    'project_senders' => '0',
    'import_without_dmarc_pass' => '0',
    'import_spam' => '0'
  }.freeze

  class << self
    def settings
      DEFAULTS.merge(Setting.plugin_redmine_serverless_ses.to_h.transform_keys(&:to_s))
    end

    def per_project_addresses?
      settings['per_project_addresses'] == '1'
    end

    def project_senders?
      settings['project_senders'] == '1'
    end

    # Redmine's subdomain, after the @ of every address: the domain of the
    # emission address (Setting.mail_from).
    def domain
      Mail::Address.new(Setting.mail_from.to_s).domain.to_s.downcase.presence
    rescue Mail::Field::ParseError
      nil
    end

    def global_local_part
      settings['global_local_part'].to_s.downcase.presence || DEFAULTS['global_local_part']
    end

    def global_address
      domain && "#{global_local_part}@#{domain}"
    end

    # The bucket where SES stores received email (inbound/, processed/).
    def mail_bucket
      ENV.fetch('REDMINE_MAIL_BUCKET', '').presence
    end

    # The process that runs jobs (docs/setup.md#configuration).
    def worker?
      ENV.fetch('REDMINE_ROLE', '') == 'worker'
    end

    # Called from init.rb, on every code reload.
    def setup
      apply_worker_settings
      DeliveryJobPatch.install
      ProjectPatch.install
      ProjectSettingsTab.install
      register_admin
      RedmineServerlessSqsBoot.allow_job('ServerlessReimportMailJob') if defined?(RedmineServerlessSqsBoot)
    end

    # SES errors reach the mail job only when delivery errors are raised;
    # Redmine's production.rb turns them off. Only in the worker, so that
    # one failed message does not stop a rake task.
    def apply_worker_settings
      ActionMailer::Base.raise_delivery_errors = true if worker?
    end

    private

    def register_admin
      RedmineServerlessAdmin.register_tab(:mail_sending,
                                          label: :label_serverless_mail_sending,
                                          url: { controller: 'serverless_mail_sending', action: 'index' },
                                          position: 30)
      RedmineServerlessAdmin.register_tab(:mail_receiving,
                                          label: :label_serverless_mail_receiving,
                                          url: { controller: 'serverless_mail_receiving', action: 'index' },
                                          position: 40)
      RedmineServerlessAdmin.register_check(:ses, label: :label_serverless_check_ses) { SesAccount.new.check }
    end
  end
end
