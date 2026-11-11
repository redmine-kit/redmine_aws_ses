# frozen_string_literal: true

module RedmineAws
  module SES
    # Imports one message that SES stored in the mail bucket
    # (rake redmine_aws_ses:receive_mail; Serverless docs/mail.md#importing):
    # checks the verdicts of the SES event, chooses the project from the
    # event's recipients, reads the message from inbound/ (or processed/ for a
    # re-import), passes it to Redmine's MailHandler, and moves it to
    # processed/. Each run leaves a record (AwsSesReceivedMail), which keeps
    # the event's verdicts and recipients for re-imports.
    class Receiver
      INBOUND = 'inbound/'
      PROCESSED = 'processed/'
      MESSAGE_ID = /\A[A-Za-z0-9._-]{1,128}\z/

      # recipients and verdicts: from the SES event (Verdicts::FIELDS). Without
      # them, a re-import uses the ones recorded by the first run.
      def initialize(message_id, recipients: nil, verdicts: nil, s3_client: Clients.s3,
                     bucket: RedmineAws::SES.mail_bucket)
        raise ArgumentError, "invalid message ID: #{message_id.inspect}" unless MESSAGE_ID.match?(message_id.to_s)
        raise ArgumentError, 'REDMINE_MAIL_BUCKET is not set' unless bucket

        @message_id = message_id
        @recipients = Array(recipients).map { |address| address.to_s.strip.downcase }.compact_blank.presence
        @verdicts = verdicts.presence
        @s3 = s3_client
        @bucket = bucket
      end

      def run
        key, raw = fetch
        mail = Mail.new(raw)
        record = AwsSesReceivedMail.find_or_initialize_by(message_id: @message_id)
        record.assign_attributes(s3_key: key, mail_from: mail.from&.first.to_s.first(255),
                                 subject: mail.subject.to_s.first(255), received_at: mail.date || Time.current,
                                 processed_at: Time.current)
        record.recipients = @recipients.join(', ') if @recipients
        record.verdicts = @verdicts if @verdicts
        import(raw, mail, record, key)
        record.save!
        record
      end

      private

      # Tries the key recorded by an earlier run first. Without s3:ListBucket,
      # S3 answers a missing key with AccessDenied instead of NoSuchKey.
      def fetch
        error = nil
        prefixes.each do |prefix|
          key = prefix + @message_id
          return [key, @s3.get_object(bucket: @bucket, key: key).body.read]
        rescue ::Aws::S3::Errors::NoSuchKey, ::Aws::S3::Errors::AccessDenied => e
          error = e
        end
        raise ArgumentError, "no message #{@message_id} in #{@bucket} (#{error.class.name.demodulize})"
      end

      def prefixes
        recorded = AwsSesReceivedMail.find_by(message_id: @message_id)&.s3_key.to_s
        recorded.start_with?(PROCESSED) ? [PROCESSED, INBOUND] : [INBOUND, PROCESSED]
      end

      def import(raw, mail, record, key)
        reason = Verdicts.reason(record.verdicts) || (auto_reply?(mail) && 'auto_reply')
        return drop(record, reason) if reason

        target = Routing.new.target(record.recipient_list)
        return drop(record, 'no_project') unless target

        record.project = target.project
        result = MailHandler.safe_receive(raw, options(target))
        return drop(record, 'import_error') unless result

        record.status = 'imported'
        record.reason = nil
        record.target_type = result.class.name
        record.target_id = result.id
        move_to_processed(key)
        record.s3_key = PROCESSED + @message_id
      end

      def drop(record, reason)
        record.status = 'dropped'
        record.reason = reason
        Rails.logger.info "[redmine_aws_ses] dropped #{@message_id}: #{reason}"
      end

      def auto_reply?(mail)
        MailHandler.ignored_emails_headers.any? do |name, ignored|
          value = mail.header[name]&.to_s&.downcase
          value && (ignored.is_a?(Regexp) ? ignored.match?(value) : value == ignored)
        end
      end

      # MailHandler's options, as rake redmine:email:read builds them. The
      # project is not overridable, so a Project: keyword cannot change it.
      def options(target)
        setting = target.setting
        issue = { project: target.project.identifier }
        issue.merge!(setting.issue_defaults) if setting
        { issue: issue, unknown_user: setting&.unknown_user.presence || 'ignore',
          no_permission_check: '0', allow_override: '' }
      end

      def move_to_processed(key)
        return if key.start_with?(PROCESSED)

        @s3.copy_object(bucket: @bucket, copy_source: "#{@bucket}/#{key}", key: PROCESSED + @message_id)
        @s3.delete_object(bucket: @bucket, key: key)
      end
    end
  end
end
