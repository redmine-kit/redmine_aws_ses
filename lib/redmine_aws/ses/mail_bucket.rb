# frozen_string_literal: true

module RedmineAws
  module SES
    # The mail bucket, where SES stores each received message
    # (docs/receiving.md#importing): inbound/<message ID> until it is
    # imported, processed/<message ID> after.
    class MailBucket
      INBOUND = 'inbound/'
      PROCESSED = 'processed/'
      # Enough for the headers of a message that is not read whole.
      HEADER_BYTES = 64 * 1024

      def initialize(client:, bucket:)
        @s3 = client
        @bucket = bucket
      end

      # The key and the size of the message, trying the key of an earlier run
      # first. Without s3:ListBucket, S3 answers a missing key with 403
      # instead of 404.
      def locate(message_id, recorded_key = nil)
        error = nil
        prefixes(recorded_key).each do |prefix|
          key = prefix + message_id
          return [key, @s3.head_object(bucket: @bucket, key: key).content_length.to_i]
        rescue ::Aws::S3::Errors::NotFound, ::Aws::S3::Errors::Forbidden,
               ::Aws::S3::Errors::NoSuchKey, ::Aws::S3::Errors::AccessDenied => e
          error = e
        end
        raise ArgumentError, "no message #{message_id} in #{@bucket} (#{error.class.name.demodulize})"
      end

      # The message as bytes, as MailHandler.receive reads it (raw_mail.b):
      # the body is tagged UTF-8, and 8-bit text in it is not. bytes: only the
      # first bytes.
      def read(key, bytes: nil)
        params = { bucket: @bucket, key: key, range: bytes && "bytes=0-#{bytes - 1}" }.compact
        @s3.get_object(**params).body.read.b
      end

      # Moves an imported message to processed/; returns its key there.
      def move_to_processed(key, message_id)
        target = PROCESSED + message_id
        return target if key == target

        @s3.copy_object(bucket: @bucket, copy_source: "#{@bucket}/#{key}", key: target)
        @s3.delete_object(bucket: @bucket, key: key)
        target
      end

      private

      def prefixes(recorded_key)
        recorded_key.to_s.start_with?(PROCESSED) ? [PROCESSED, INBOUND] : [INBOUND, PROCESSED]
      end
    end
  end
end
