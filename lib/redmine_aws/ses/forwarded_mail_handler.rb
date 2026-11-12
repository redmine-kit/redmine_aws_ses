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
    # It overrides private methods of MailHandler, as there is no option for
    # them: dispatch, to put the author in place of the user that
    # MailHandler#receive took from the From address (and in User.current, as
    # #receive does); add_watchers, to check the forwarder's permission
    # instead of the author's; and the reply methods (below). All call super.
    # The forwarded email tests fail if Redmine changes them.
    class ForwardedMailHandler < ::MailHandler
      # A reply (by In-Reply-To, References or the subject) to something of a
      # project other than the one the envelope recipient chose
      # (:aws_ses_project_id), or of a kind the guard does not know. A
      # message let in by a registered forwarder has a From that nothing
      # authenticated, so it may reply only within that project; Import
      # records it as not fetched ("forwarded_reply"). A member's forward
      # never gets here as a reply: ForwardedMail drops the original's
      # In-Reply-To and References and refuses an original whose subject
      # names an issue or a message.
      class OtherProjectReply < StandardError; end

      # The kinds of reply MailHandler#dispatch reaches by the message ID of
      # a notification (receive_<kind>_reply), each checked below: an allow
      # list, so that a kind Redmine adds later is refused until it is
      # checked here (a test compares it with MailHandler's methods).
      REPLY_KINDS = %w[issue journal message news comment].freeze

      private

      # Before MailHandler#dispatch: a reply by message ID of a kind not in
      # REPLY_KINDS is refused.
      def refuse_unknown_reply_kind!
        header = [email.in_reply_to, email.references].flatten.compact.find { |h| MESSAGE_ID_RE.match?(h.to_s) }
        kind = header && MESSAGE_ID_RE.match(header.to_s)[1]
        raise OtherProjectReply, "reply of a kind that is not checked (#{kind})" if kind && REPLY_KINDS.exclude?(kind)
      end

      # The reply methods of MailHandler check only the author's permission:
      # the target must be in the routed project. receive_journal_reply goes
      # through receive_issue_reply, receive_comment_reply through
      # receive_news_reply.
      def receive_issue_reply(issue_id, from_journal = nil)
        routed!(Issue.find_by(id: issue_id)&.project)
        super
      end

      def receive_message_reply(message_id)
        routed!(Message.find_by(id: message_id)&.root&.project)
        super
      end

      def receive_news_reply(news_id)
        routed!(News.find_by(id: news_id)&.project)
        super
      end

      def routed!(project)
        return if project.nil? || project.id == handler_options[:aws_ses_project_id]

        raise OtherProjectReply, "reply to another project (#{project.identifier})"
      end

      def dispatch
        id = handler_options[:aws_ses_author_id].to_i
        @user = id.zero? ? User.anonymous : User.find(id)
        User.current = @user
        refuse_unknown_reply_kind!
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
