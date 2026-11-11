# frozen_string_literal: true

module RedmineAws
  module SES
    # The import tests on moto's (or LocalStack's) S3: a mail bucket per test,
    # with messages as SES stores them.
    module MailBucketHelper
      def self.included(base)
        base.setup { create_mail_bucket }
        base.teardown { delete_mail_bucket }
      end

      def create_mail_bucket
        @s3 = ::Aws::S3::Client.new(endpoint: ENV.fetch('AWS_ENDPOINT_URL'), force_path_style: true)
        @bucket = "redmine-mail-#{SecureRandom.hex(4)}"
        @s3.create_bucket(bucket: @bucket)
        RedmineAws::SES::Clients.s3 = @s3
        ActionMailer::Base.deliveries.clear
      end

      def delete_mail_bucket
        return unless @bucket

        @s3.list_objects_v2(bucket: @bucket).contents.each { |o| @s3.delete_object(bucket: @bucket, key: o.key) }
        @s3.delete_bucket(bucket: @bucket)
      end

      def store(raw)
        id = SecureRandom.hex(10)
        @s3.put_object(bucket: @bucket, key: "inbound/#{id}", body: raw)
        id
      end

      def keys
        @s3.list_objects_v2(bucket: @bucket).contents.map(&:key)
      end

      # options: the event's values (recipients:, verdicts:, envelope_from:) and
      # the plugin's settings.
      def receive(raw, id: nil, max_bytes: RedmineAws::SES::Receiver::MAX_BYTES, **options)
        id ||= store(raw)
        event = { recipients: ["ecookbook@#{TestHelper::DOMAIN}"], verdicts: TestHelper::PASS }
                .merge(options.extract!(:recipients, :verdicts, :envelope_from))
        with_env('REDMINE_MAIL_BUCKET' => @bucket) do
          with_ses_settings({ 'per_project_addresses' => '1' }.merge(options)) do
            project_setting
            RedmineAws::SES::Receiver.new(id, event: event, max_bytes: max_bytes).run
          end
        end
      end

      def project_setting
        AwsSesProjectMailSetting.find_or_create_by!(project_id: 1) do |setting|
          setting.receive = true
          setting.tracker_id = 2
        end
      end
    end
  end
end
