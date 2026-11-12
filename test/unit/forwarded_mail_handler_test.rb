# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # ForwardedMailHandler overrides private methods of Redmine's
    # MailHandler; the forwarded email tests (test/integration) check their
    # effect. These fail first if Redmine renames or changes them.
    class ForwardedMailHandlerTest < ActiveSupport::TestCase
      def test_the_methods_it_overrides
        %i[dispatch add_watchers receive_issue_reply receive_message_reply].each do |name|
          assert MailHandler.private_method_defined?(name), name
          assert_equal MailHandler, RedmineAws::SES::ForwardedMailHandler.instance_method(name).super_method.owner, name
        end
        assert_equal 1, MailHandler.instance_method(:add_watchers).arity
        assert_equal [%i[req issue_id], %i[opt from_journal]],
                     MailHandler.instance_method(:receive_issue_reply).parameters
      end
    end
  end
end
