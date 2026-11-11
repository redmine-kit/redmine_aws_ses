# frozen_string_literal: true

module RedmineAws
  module SES
    # The original of an email that a member forwarded from their mail client
    # (docs/receiving.md#forwarded-email): a message attached as
    # message/rfc822 (forward as attachment), or the forwarded block that
    # Gmail and Outlook put in the body (InlineForward), with Fwd:, FW: or
    # 転送: before the subject. The original is untrusted content like any
    # received email: it only gives the issue's sender, subject, body and
    # attachments, and Admission decides whether it is used at all.
    class ForwardedMail
      SUBJECT_PREFIX = /\A\s*(?:fwd?|転送)\s*[:：]/i

      # raw and sender: the original's; note_text and note_attachments: the
      # forwarder's own text and attachments around it, which the forwarder's
      # note keeps (ForwardNote).
      attr_reader :raw, :sender, :note_text, :note_attachments

      # The original, or nil when the message is not a forward that can be
      # used: no Fwd:, FW: or 転送: before the subject, no original or more
      # than one, no sender, the forwarder's own message, a reply, or larger
      # than max_bytes. Anything that fails to parse is not a forward either;
      # the message is then imported as the forwarder's own.
      def self.parse(mail, max_bytes:)
        return unless SUBJECT_PREFIX.match?(mail.subject.to_s)

        forward = attached(mail) || inline(mail)
        forward if forward&.usable?(mail, max_bytes)
      rescue StandardError => e
        Rails.logger.info "[redmine_aws_ses] not a forward that can be read: #{e.class}"
        nil
      end

      def self.attached(mail)
        parts = mail.all_parts.select { |part| rfc822?(part) }
        return unless parts.one?

        new(Mail.new(parts.first.body.decoded.b), note_text: InlineForward.text(mail).to_s.strip,
                                                  note_attachments: outer_attachments(mail))
      end

      def self.rfc822?(part)
        part.mime_type == 'message/rfc822'
      end

      # The forward's own attachments: those outside the attached message,
      # which the mail gem lists among the forward's attachments too.
      def self.outer_attachments(part)
        part.parts.flat_map do |child|
          if rfc822?(child) then []
          elsif child.multipart? then outer_attachments(child)
          else child.attachment? ? [child] : []
          end
        end
      end

      # The attachments of an inline forward are the original's.
      def self.inline(mail)
        original, preamble = InlineForward.new(mail).parse
        original && new(original, note_text: preamble, note_attachments: [])
      end

      # Without the headers that would make Redmine add it to an existing
      # issue (MailHandler#dispatch reads In-Reply-To and References).
      def initialize(original, note_text: '', note_attachments: [])
        @note_text = note_text
        @note_attachments = note_attachments
        original.header['In-Reply-To'] = nil
        original.header['References'] = nil
        @subject = original.subject.to_s
        @sender = Array(original.from).first.to_s.strip.downcase
        @raw = original.to_s.b
      end

      def usable?(mail, max_bytes)
        URI::MailTo::EMAIL_REGEXP.match?(sender) && !sender.casecmp?(Array(mail.from).first.to_s.strip) &&
          raw.bytesize <= max_bytes && !reply?
      end

      private

      # A reply to a notification: Redmine would add it to that issue or
      # message as a note of the original sender (MailHandler#dispatch), so
      # it is imported as the forwarder's own message instead.
      def reply?
        MailHandler::ISSUE_REPLY_SUBJECT_RE.match?(@subject) || MailHandler::MESSAGE_REPLY_SUBJECT_RE.match?(@subject)
      end
    end
  end
end
