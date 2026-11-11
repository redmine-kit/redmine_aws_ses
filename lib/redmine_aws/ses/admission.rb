# frozen_string_literal: true

module RedmineAws
  module SES
    # The decisions about one received message (docs/receiving.md), in one
    # place: whether it may be imported (and why not), its project, and whose
    # message it is. Everything comes from the SES event as recorded
    # (verdicts, envelope recipients, envelope sender) and from Redmine; the
    # message's headers decide nothing, as a sender can forge them. Import
    # carries the decisions out.
    #
    # - The project: from the envelope recipients (Routing), so email that an
    #   external mailbox (support@company.example) forwards to a project's
    #   address goes to that project, whatever its To header says.
    # - Forwarders: a message that fails DMARC is imported when it came
    #   through a registered forwarder of the project: SES's SPF check passed
    #   for the envelope sender (MAIL FROM), and that sender is the
    #   forwarder's (via_forwarder?). Forwarding breaks DMARC; Microsoft 365
    #   (SRS) and Gmail put the forwarder's address in MAIL FROM.
    # - Forwards by members: when the project takes them, a forward by an
    #   active user who may add issues to the project, whose own message
    #   passed DMARC, is imported as its original (forward, forwarder).
    # - The author of forwarded email (both kinds): the original sender only
    #   when the project's setting lets that sender be the author; otherwise
    #   the member who forwarded, or the anonymous user (author).
    class Admission
      def initialize(record, mail, settings: RedmineAws::SES.settings, max_bytes: Receiver::MAX_BYTES)
        @record = record
        @mail = mail
        @settings = settings
        @max_bytes = max_bytes
      end

      def target
        return @target if defined?(@target)

        @target = Routing.new(settings: @settings).target(@record.recipient_list)
      end

      # nil when the message may be imported; otherwise the reason it is not
      # (AwsSesReceivedMail::REASONS).
      def reason
        return @reason if defined?(@reason)

        @reason = verdict_reason || other_reason
      end

      def via_forwarder?
        forwarder_sender? && verdicts[:spf] == 'PASS'
      end

      # Imported only because a registered forwarder sent it: its From is not
      # authenticated.
      def exempted?
        via_forwarder? && verdicts[:dmarc] != 'PASS'
      end

      # The issue's author for forwarded email (a member's forward, or a
      # message exempted through a registered forwarder), as the project's
      # forwarded_author allows: the original sender's user; for a sender
      # Redmine does not know, the anonymous user when the project fetches
      # from unknown senders; otherwise the member who forwarded, or for an
      # automatic forward the anonymous user when the project fetches from
      # unknown senders. nil: not forwarded (Redmine's MailHandler takes the
      # sender), or no author is allowed (the message is not imported).
      def author
        return @author if defined?(@author)

        @author = (choose_author(forward ? forward.sender : sender_address) if forward || exempted?)
      end

      # The original of a forward by a member (ForwardedMail), or nil: the
      # message is then imported as the sender's own.
      def forward
        return @forward if defined?(@forward)

        @forward = forwarder && ForwardedMail.parse(@mail, max_bytes: @max_bytes)
      end

      # The member who forwarded, when the project takes forwards: the active
      # user with the sender's address, whose message passed DMARC (so the
      # address is the sender's), and who may add issues to the project.
      def forwarder
        return @forwarder if defined?(@forwarder)

        @forwarder = (find_forwarder if target&.setting&.import_forwarded? && verdicts[:dmarc] == 'PASS')
      end

      private

      def verdicts
        @record.verdicts.to_h
      end

      # A failed DMARC check of a registered forwarder's message whose SPF
      # check did not pass has a reason of its own, to tell the two apart in
      # the list of received email.
      def verdict_reason
        reason = Verdicts.reason(@record.verdicts, @settings, dmarc_excused: via_forwarder?)
        reason == 'dmarc' && forwarder_sender? ? 'forwarder_spf' : reason
      end

      def other_reason
        return 'auto_reply' if auto_reply?
        return 'no_project' unless target

        'forwarded_author' if exempted? && author.nil?
      end

      def forwarder_sender?
        target&.setting&.forwarder?(@record.envelope_from) || false
      end

      def find_forwarder
        user = User.active.find_by_mail(sender_address)
        user if user&.allowed_to?(:add_issues, target.project)
      end

      def sender_address
        Array(@mail.from).first.to_s.strip
      end

      def choose_author(address)
        setting = target.setting
        user = User.find_by_mail(address)
        return user if setting.forwarded_author?(user)
        return User.anonymous if user.nil? && setting.forwarded_author != 'forwarder' && setting.unknown_senders?

        forwarder || (User.anonymous if setting.unknown_senders?)
      end

      # Auto-replies, by the headers that Redmine's MailHandler ignores.
      def auto_reply?
        MailHandler.ignored_emails_headers.any? do |name, ignored|
          value = @mail.header[name]&.to_s&.downcase
          value && (ignored.is_a?(Regexp) ? ignored.match?(value) : value == ignored)
        end
      end
    end
  end
end
