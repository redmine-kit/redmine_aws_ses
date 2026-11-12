# frozen_string_literal: true

module RedmineAws
  module SES
    # Imports a received message into Redmine as Admission decides
    # (docs/receiving.md#importing): passes it, or the original of a member's
    # forward, to Redmine's MailHandler with the project's options, and fills
    # the record with the result. The record is saved by the Receiver, in the
    # same transaction.
    #
    # The transaction has no savepoints (some databases have none): when
    # MailHandler refuses a message, Refused is raised, which rolls back
    # whatever MailHandler wrote, and the Receiver runs again with the next
    # mode: a refused forward as the member's own message (:own), a refused
    # message as not fetched, the mode being the reason ("import_error", or
    # "forwarded_reply" for a reply to another project through a registered
    # forwarder), so nothing is lost.
    class Import
      # MailHandler did not take the message; forward: it was a member's
      # forwarded original.
      class Refused < StandardError
        attr_reader :forward, :reason

        def initialize(forward, reason = 'import_error')
          @forward = forward
          @reason = reason
          super(forward ? 'forwarded original refused' : "message refused (#{reason})")
        end
      end

      def initialize(record, raw, mail, mode: :full, max_bytes: Receiver::MAX_BYTES)
        @record = record
        @raw = raw
        @mail = mail
        @mode = mode
        @max_bytes = max_bytes
      end

      def run
        admission = Admission.new(@record, @mail, max_bytes: @max_bytes)
        return drop(admission.reason) if admission.reason
        return drop(@mode) if @mode.is_a?(String)

        @record.project = admission.target.project
        @record.mark_imported(@mode == :full && admission.forward ? forwarded(admission) : own(admission))
      end

      private

      # The original of a member's forward, by the author Admission chose,
      # with the forwarder as a watcher and a note by the forwarder
      # (ForwardNote).
      def forwarded(admission)
        options = options(admission.target, admission.author, admission.forwarder)
        result = receive(admission.forward.raw, options) or raise Refused, true
        ForwardNote.new(result, admission.forwarder, admission.forward).add if result.is_a?(Issue)
        result
      end

      # The message itself; by the author Admission chose when a registered
      # forwarder let it in.
      def own(admission)
        author = admission.author unless admission.forward
        receive(@raw, options(admission.target, author, nil)) or raise Refused, false
      end

      def receive(raw, options)
        return MailHandler.safe_receive(raw, options) unless options.key?(:aws_ses_author_id)

        receive_forwarded(raw, options)
      end

      # As MailHandler.safe_receive, except a reply to another project, which
      # is refused with a reason of its own (ForwardedMailHandler).
      def receive_forwarded(raw, options)
        ForwardedMailHandler.receive(raw, options)
      rescue ForwardedMailHandler::OtherProjectReply => e
        Rails.logger.info "[redmine_aws_ses] #{@record.message_id}: #{e.message}"
        raise Refused.new(false, 'forwarded_reply')
      rescue StandardError => e
        Rails.logger.error "MailHandler: an unexpected error occurred when receiving email: #{e.message}"
        false
      end

      def drop(reason)
        @record.mark_dropped(reason)
        Rails.logger.info "[redmine_aws_ses] dropped #{@record.message_id}: #{reason}"
      end

      # MailHandler's options, as rake redmine:email:read builds them. The
      # project is not overridable, so a Project: keyword cannot change it.
      # With an author (ForwardedMailHandler), unknown senders are accepted,
      # as the author takes their place, and no user is ever created.
      def options(target, author, forwarder)
        setting = target.setting
        issue = { project: target.project.identifier }
        issue.merge!(setting.issue_defaults) if setting
        options = { issue: issue, unknown_user: setting&.unknown_user.presence || 'ignore',
                    no_permission_check: '0', allow_override: '' }
        return options unless author

        options.merge(unknown_user: 'accept', aws_ses_author_id: author.anonymous? ? 0 : author.id,
                      aws_ses_forwarder_id: forwarder&.id, aws_ses_project_id: target.project.id)
      end
    end
  end
end
