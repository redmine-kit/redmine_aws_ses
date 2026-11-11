# frozen_string_literal: true

module RedmineAws
  module SES
    # Redmine's MailHandler for forwarded email (docs/receiving.md#forwarded-email),
    # with the author that Admission chose (handler option :aws_ses_author_id,
    # 0 for the anonymous user) and the watchers from the original's To and Cc
    # added with the rights of the member who forwarded (:aws_ses_forwarder_id;
    # no watchers without one). Import passes unknown_user "accept", so that
    # MailHandler never creates a user from an original sender.
    #
    # It overrides two private methods of MailHandler, as there is no option
    # for either: dispatch, to put the author in place of the user that
    # MailHandler#receive took from the From address (and in User.current, as
    # #receive does), and add_watchers, to check the forwarder's permission
    # instead of the author's. Both call super. The forwarded email tests
    # fail if Redmine changes them.
    class ForwardedMailHandler < ::MailHandler
      private

      def dispatch
        id = handler_options[:aws_ses_author_id].to_i
        @user = id.zero? ? User.anonymous : User.find(id)
        User.current = @user
        super
      end

      def add_watchers(obj)
        forwarder = User.find_by(id: handler_options[:aws_ses_forwarder_id])
        return unless forwarder

        author = @user
        @user = forwarder
        begin
          super
        ensure
          @user = author
        end
      end
    end
  end
end
