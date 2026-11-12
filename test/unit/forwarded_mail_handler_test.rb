# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # ForwardedMailHandler overrides private methods of Redmine's
    # MailHandler; the forwarded email tests (test/integration) check their
    # effect. These fail first if Redmine renames or changes them.
    class ForwardedMailHandlerTest < ActiveSupport::TestCase
      def test_the_methods_it_overrides
        %i[dispatch add_watchers receive_issue_reply receive_message_reply receive_news_reply].each do |name|
          assert MailHandler.private_method_defined?(name), name
          assert_equal MailHandler, RedmineAws::SES::ForwardedMailHandler.instance_method(name).super_method.owner, name
        end
        assert_equal 1, MailHandler.instance_method(:add_watchers).arity
        assert_equal [%i[req issue_id], %i[opt from_journal]],
                     MailHandler.instance_method(:receive_issue_reply).parameters
      end

      # Every kind of reply MailHandler#dispatch can reach by a message ID is
      # one the guard checks: a kind Redmine adds fails here first.
      def test_the_reply_kinds_are_those_of_mail_handler
        kinds = MailHandler.private_instance_methods.filter_map { |name| name.to_s[/\Areceive_(\w+)_reply\z/, 1] }

        assert_equal RedmineAws::SES::ForwardedMailHandler::REPLY_KINDS.sort, kinds.sort
      end
    end
  end
end
