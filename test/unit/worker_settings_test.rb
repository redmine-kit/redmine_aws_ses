# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # raise_delivery_errors is true only in the process that runs jobs.
    class WorkerSettingsTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper

      def setup
        @saved = ActionMailer::Base.raise_delivery_errors
        ActionMailer::Base.raise_delivery_errors = false
      end

      def teardown
        ActionMailer::Base.raise_delivery_errors = @saved
      end

      def test_true_in_the_worker
        with_env('REDMINE_ROLE' => 'worker') { RedmineAws::SES.apply_worker_settings }

        assert ActionMailer::Base.raise_delivery_errors
      end

      def test_unchanged_elsewhere
        %w[web task].push(nil).each do |role|
          with_env('REDMINE_ROLE' => role) { RedmineAws::SES.apply_worker_settings }

          assert_not ActionMailer::Base.raise_delivery_errors, role.inspect
        end
      end
    end
  end
end
