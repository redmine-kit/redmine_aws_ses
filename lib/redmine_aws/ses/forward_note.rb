# frozen_string_literal: true

module RedmineAws
  module SES
    # The forwarder's part of an issue made from a member's forward
    # (docs/receiving.md#forwarding-by-members): the forwarder as a watcher,
    # when they can see the issue, and, when they may add notes, a note by
    # the forwarder that names the original sender and keeps the forward's
    # own text and attachments. Written as Redmine writes the notes of
    # commits (Changeset#fix_issue: init_journal, then save), so that
    # Redmine's rules and notifications apply.
    class ForwardNote
      def initialize(issue, forwarder, forward)
        @issue = issue
        @forwarder = forwarder
        @forward = forward
      end

      # The issue as it is now: MailHandler saves it more than once.
      def add
        @issue.reload
        @issue.add_watcher(@forwarder) if watcher?
        return unless @forwarder.allowed_to?(:add_issue_notes, @issue.project)

        @issue.init_journal(@forwarder, notes)
        @forward.note_attachments.each { |part| attach(part) if accepted?(part) }
        Rails.logger.warn "[redmine_aws_ses] could not add the forwarder's note to ##{@issue.id}" unless @issue.save
      end

      private

      def watcher?
        @issue.author != @forwarder && !@issue.watched_by?(@forwarder) && @issue.visible?(@forwarder)
      end

      # In Redmine's default language, as commit notes are.
      def notes
        line = ::I18n.t(:text_aws_ses_mail_forwarded, sender: @forward.sender, locale: Setting.default_language)
        [line, @forward.note_text.presence].compact.join("\n\n")
      end

      # MailHandler's own check of attachments (the excluded file names of
      # Redmine's settings), private in Redmine; the forwarded email tests fail
      # if it changes.
      def accepted?(part)
        part.body.decoded.present? && MailHandler.new.send(:accept_attachment?, part)
      end

      # As MailHandler#add_attachments saves the attachments of email; the
      # issue's journal records them.
      def attach(part)
        @issue.attachments << Attachment.new(file: part.decoded, filename: part.filename.to_s,
                                             author: @forwarder, content_type: part.mime_type)
      end
    end
  end
end
