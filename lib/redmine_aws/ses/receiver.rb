# frozen_string_literal: true

module RedmineAws
  module SES
    # Imports one message that SES stored in the mail bucket
    # (rake redmine_aws_ses:receive_mail; docs/receiving.md#importing): reads
    # the message from inbound/ (or processed/ for a re-import), imports it as
    # Admission decides (Import), and moves it to processed/. Each run leaves
    # a record (AwsSesReceivedMail), which keeps the event's verdicts,
    # recipients and envelope sender for re-imports.
    class Receiver
      MESSAGE_ID = /\A[A-Za-z0-9._-]{1,128}\z/
      # SES's limit for email it delivers to S3: "the default maximum email
      # size (including headers) is 40 MB" (SES Developer Guide, "Deliver to S3
      # bucket action", checked 2026-11-12). A larger message is recorded and
      # not imported.
      MAX_BYTES = 40 * 1024 * 1024
      ENVELOPE_FROM = /\A[^@\s]{1,64}@[^@\s]{1,255}\z/

      # event: from the SES event, recipients (receipt.recipients), verdicts
      # (Verdicts::FIELDS) and envelope_from (mail.source, the MAIL FROM
      # address). Without them, a re-import uses the ones recorded by the first
      # run. max_bytes: for the tests.
      def initialize(message_id, event: {}, s3_client: Clients.s3, bucket: RedmineAws::SES.mail_bucket,
                     max_bytes: MAX_BYTES)
        raise ArgumentError, "invalid message ID: #{message_id.inspect}" unless MESSAGE_ID.match?(message_id.to_s)
        raise ArgumentError, 'REDMINE_MAIL_BUCKET is not set' unless bucket

        @message_id = message_id
        read_event(event)
        @bucket = MailBucket.new(client: s3_client, bucket: bucket)
        @max_bytes = max_bytes
      end

      def run
        record = import(:full)
        if record.status == 'imported'
          key = @bucket.move_to_processed(record.s3_key, @message_id)
          record.update_column(:s3_key, key) unless key == record.s3_key
        end
        record
      end

      private

      # A run in a mode of Import (:full, then :own for a refused forward, then
      # :refused): each in a transaction of its own, as nothing is rolled back
      # to a savepoint.
      def import(mode)
        serialized { |locked| receive(locked, mode) }
      rescue Import::Refused => e
        import(e.forward ? :own : e.reason)
      end

      def read_event(event)
        @recipients = Array(event[:recipients]).map { |address| address.to_s.strip.downcase }.compact_blank.presence
        @verdicts = event[:verdicts].presence
        envelope_from = event[:envelope_from].to_s.strip.downcase
        @envelope_from = envelope_from if ENVELOPE_FROM.match?(envelope_from)
      end

      # The record of the message, locked in a transaction (SELECT ... FOR
      # UPDATE), so that runs for the same message (SES's retry, a re-import)
      # run one after the other and one mail never creates two issues. Two
      # first runs meet at the unique index of message_id: the second fails,
      # which rolls back what it created, and runs again on the first's record.
      # A conflict with a concurrent transaction (a serialization failure or
      # a deadlock) is retried once too. The import itself opens no nested
      # transaction; requires_new matters only when the caller already has
      # one (the tests' transactions).
      def serialized(&)
        attempts = 0
        begin
          AwsSesReceivedMail.transaction(requires_new: true) { locked_record.tap(&) }
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid, ActiveRecord::SerializationFailure,
               ActiveRecord::Deadlocked => e
          attempts += 1
          retry if attempts == 1 && retryable?(e)
          raise
        end
      end

      def locked_record
        AwsSesReceivedMail.lock.find_by(message_id: @message_id) || AwsSesReceivedMail.new(message_id: @message_id)
      end

      # The other run's record came first (at the unique index, or at the
      # model's uniqueness check when the other run had committed already),
      # or the database asks to run the transaction again.
      def retryable?(error)
        return error.record.errors.of_kind?(:message_id, :taken) if error.is_a?(ActiveRecord::RecordInvalid)

        true
      end

      def receive(record, mode)
        return skip(record) if record.imported_target?

        key, size = @bucket.locate(@message_id, record.s3_key)
        remember(record, key)
        size > @max_bytes ? too_large(record, key) : import_message(record, key, mode)
        record.save!
      end

      def import_message(record, key, mode)
        Import.new(record, *read(record, key), mode: mode, max_bytes: @max_bytes).run
      end

      # Imported already, and the issue or note it created still exists.
      def skip(record)
        Rails.logger.info "[redmine_aws_ses] #{@message_id} is imported already " \
                          "(#{record.target_type} #{record.target_id})"
      end

      def remember(record, key)
        record.s3_key = key
        record.processed_at = Time.current
        record.recipients = @recipients.join(', ') if @recipients
        record.verdicts = @verdicts if @verdicts
        record.envelope_from = @envelope_from if @envelope_from
      end

      def read(record, key)
        raw = @bucket.read(key)
        mail = Mail.new(raw)
        record.describe(mail)
        [raw, mail]
      end

      # Only the headers are read, for the record.
      def too_large(record, key)
        headers = @bucket.read(key, bytes: MailBucket::HEADER_BYTES).split(/\r?\n\r?\n/, 2).first
        record.describe(Mail.new("#{headers}\r\n\r\n"))
        record.mark_dropped('too_large')
        Rails.logger.info "[redmine_aws_ses] dropped #{@message_id}: too_large"
      end
    end
  end
end
