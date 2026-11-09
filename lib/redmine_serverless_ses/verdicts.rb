# frozen_string_literal: true

module RedmineServerlessSes
  # The checks SES made when it received a message, from the SES event
  # (receipt.spamVerdict, virusVerdict, dmarcVerdict, ...; Serverless
  # docs/mail.md#spoofing-and-spam). Headers of the message are never used: a
  # sender can add headers with the same names as SES's. The verdicts are
  # recorded whether or not the message is imported.
  module Verdicts
    # Event field => record attribute and rake task variable.
    FIELDS = {
      spam: 'SES_SPAM_VERDICT', virus: 'SES_VIRUS_VERDICT', dmarc: 'SES_DMARC_VERDICT',
      dmarc_policy: 'SES_DMARC_POLICY', spf: 'SES_SPF_VERDICT', dkim: 'SES_DKIM_VERDICT'
    }.freeze

    module_function

    # The verdicts given to the rake task, or nil when none are.
    def from_env(env = ENV)
      values = FIELDS.to_h { |name, variable| [name, env.fetch(variable, '').strip.upcase.presence] }.compact
      values.presence
    end

    # nil when the message may be imported; otherwise the reason it is not.
    # A message with a virus is never imported (its attachments would be
    # served to everyone). Spam and a failed DMARC check are dropped unless
    # the receiving settings import them (import_spam,
    # import_without_dmarc_pass).
    def reason(verdicts, settings = RedmineServerlessSes.settings)
      return 'no_verdict' if verdicts.blank? || verdicts[:virus].blank?
      return 'virus' unless verdicts[:virus] == 'PASS'
      return 'spam' unless allowed?(verdicts[:spam], settings['import_spam'])
      return 'dmarc' unless allowed?(verdicts[:dmarc], settings['import_without_dmarc_pass'])

      nil
    end

    # PASS, or anything else when the setting imports it.
    def allowed?(verdict, setting)
      verdict == 'PASS' || setting == '1'
    end
  end
end
