# frozen_string_literal: true

require_relative '../test_helper'
require 'rake'

module RedmineKit
  module Aws
    module Ses
      # The rake task redmine_kit:aws:ses:prune, with DAYS as Serverless's
      # daily schedule passes it.
      class PruneTaskTest < ActiveSupport::TestCase
        include RedmineKit::Aws::Ses::TestHelper

        setup do
          Rails.application.load_tasks unless Rake::Task.task_defined?('redmine_kit:aws:ses:prune')
          AwsSesReceivedMail.create!(message_id: 'old', status: 'imported', created_at: 91.days.ago)
          AwsSesReceivedMail.create!(message_id: 'month', status: 'imported', created_at: 31.days.ago)
          AwsSesReceivedMail.create!(message_id: 'new', status: 'imported')
        end

        # The output, or the SystemExit of abort.
        def rake_prune(env)
          task = Rake::Task['redmine_kit:aws:ses:prune']
          task.reenable
          with_env({ 'DAYS' => nil }.merge(env)) { capture_io { task.invoke } }
        end

        def kept
          AwsSesReceivedMail.order(:message_id).pluck(:message_id)
        end

        def test_the_task_is_in_the_redmine_kit_namespace
          assert Rake::Task.task_defined?('redmine_kit:aws:ses:prune')
          assert_empty Rake::Task.tasks.map(&:name).grep(/\Aredmine_kit_aws_ses:/)
          assert_empty Rake::Task['redmine_kit:aws:ses:prune'].arg_names
        end

        def test_without_days_keeps_90_days
          out, = rake_prune({})

          assert_equal "deleted 1 record(s) older than 90 days\n", out
          assert_equal %w[month new], kept
        end

        def test_days_sets_the_number_of_days
          out, = rake_prune('DAYS' => '30')

          assert_equal "deleted 2 record(s) older than 30 days\n", out
          assert_equal %w[new], kept
        end

        def test_an_invalid_days_aborts_and_deletes_nothing
          ['', '0', '-1', 'abc', '30abc', '1.5', ' 30', "30\n", '100000'].each do |value|
            error = assert_raises(SystemExit, "DAYS=#{value.inspect}") { rake_prune('DAYS' => value) }

            assert_not error.success?
            assert_equal %w[month new old], kept, "DAYS=#{value.inspect}"
          end
        end

        def test_the_message_of_an_invalid_days
          assert_equal ['Invalid DAYS abc given. The value must be an integer from 1 to 99999.', false],
                       Tasks.prune('DAYS' => 'abc')
        end
      end
    end
  end
end
