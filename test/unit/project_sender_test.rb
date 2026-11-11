# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # The interceptor that sends project notifications from the project's
    # address.
    class ProjectSenderTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper

      def sent(project: 'ecookbook', from: "John Smith <redmine@#{DOMAIN}>")
        mail = Mail.new(from: from, to: 'a@b.example', subject: 's', body: 'b')
        mail['X-Redmine-Project'] = project if project
        RedmineAws::SES::ProjectSender.call(mail)
        mail
      end

      def on(&)
        with_ses_settings('per_project_addresses' => '1', 'project_senders' => '1', &)
      end

      def test_a_project_notification_comes_from_the_project
        on do
          AwsSesProjectMailSetting.create!(project: Project.find(1), receive: true)
          mail = sent

          assert_equal ["ecookbook@#{DOMAIN}"], mail.from
          assert_equal 'John Smith', mail[:from].display_names.first
          assert_nil mail.reply_to
        end
      end

      # The display name is the author's name (Redmine's Mailer#mail), which
      # the user chooses.
      def test_display_names_with_quotes_and_backslashes
        on do
          ['Foo\\', 'John "J" Smith', 'ジョン・スミス'].each do |name|
            author = Mail::Address.new("redmine@#{DOMAIN}")
            author.display_name = name
            mail = Mail.new(sent(from: author.format).encoded)

            assert_equal ["ecookbook@#{DOMAIN}"], mail.from, name
            assert_equal name, mail[:from].display_names.first, name
          end
        end
      end

      def test_replies_to_a_project_that_does_not_receive_go_to_the_emission_address
        on do
          assert_equal ["redmine@#{DOMAIN}"], sent.reply_to
        end
      end

      def test_email_without_a_project_keeps_the_emission_address
        on do
          assert_equal ["redmine@#{DOMAIN}"], sent(project: nil).from
        end
      end

      def test_off_by_default
        with_ses_settings do
          assert_equal ["redmine@#{DOMAIN}"], sent.from
        end
      end

      def test_the_interceptor_is_registered
        assert_includes Mail.class_variable_get(:@@delivery_interceptors), RedmineAws::SES::Boot::Interceptor
      end
    end
  end
end
