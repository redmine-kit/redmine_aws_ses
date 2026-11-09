# frozen_string_literal: true

# Coverage of the plugin's own files (bin/test sets PLUGIN_COVERAGE for the
# plugin's tests), written as Cobertura XML to coverage/ for Codecov. It starts
# before Redmine loads, so that boot/, lib/ and app/ are counted.
if ENV['PLUGIN_COVERAGE']
  require 'simplecov'
  require 'simplecov-cobertura'
  SimpleCov.start do
    root File.expand_path('..', __dir__)
    add_filter '/test/'
    enable_coverage :branch
    formatter SimpleCov::Formatter::CoberturaFormatter
  end
end

require File.expand_path('../../../test/test_helper', __dir__)

module RedmineServerlessSes
  module TestHelper
    DOMAIN = 'redmine.example.com'

    def self.included(base)
      base.teardown { RedmineServerlessSes::Clients.reset }
    end

    def with_ses_settings(values = {}, &)
      saved = Setting.plugin_redmine_serverless_ses
      Setting.plugin_redmine_serverless_ses = RedmineServerlessSes::DEFAULTS.merge(values)
      with_settings(mail_from: "Redmine <redmine@#{DOMAIN}>", &)
    ensure
      Setting.plugin_redmine_serverless_ses = saved
    end

    def with_env(values)
      saved = values.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
      values.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
      yield
    ensure
      saved.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
    end

    def stub_ses(**responses)
      RedmineServerlessSes::Clients.ses = Aws::SESV2::Client.new(stub_responses: responses)
    end

    PASS = { spam: 'PASS', virus: 'PASS', dmarc: 'PASS', dmarc_policy: 'NONE', spf: 'PASS', dkim: 'PASS' }.freeze

    # A received message as the sender sent it. SES's own headers are not
    # added: the plugin reads SES's verdicts from the event, never from
    # headers, and headers: can add forged ones.
    def ses_message(to: "ecookbook@#{DOMAIN}", from: 'John Smith <jsmith@somenet.foo>', subject: 'Received by SES',
                    body: 'A new issue from email.', headers: {})
      sender = headers.map { |k, v| "#{k}: #{v}\n" }.join
      <<~MAIL
        Received: from client by mail.somenet.foo
        #{sender}From: #{from}
        To: #{to}
        Subject: #{subject}
        Message-ID: <#{SecureRandom.hex(8)}@somenet.foo>
        Date: #{Time.now.rfc2822}
        Content-Type: text/plain; charset=utf-8

        #{body}
      MAIL
    end

    # Runs the block with ActiveJob's test adapter (Redmine's tests run jobs
    # inline).
    def with_test_adapter
      saved = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      yield
    ensure
      ActiveJob::Base.queue_adapter = saved
    end
  end
end
