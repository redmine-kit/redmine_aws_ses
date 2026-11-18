# frozen_string_literal: true

require_relative '../test_helper'
require 'open3'

module RedmineKit
  module Aws
    module Ses
      # The plugin's code is under the RedmineKit::Aws namespace of redmine_kit_aws
      # (lib/redmine_kit/aws/ses.rb), and its boot file defines RedmineKit::Aws::Ses::Boot
      # before Redmine's code loader (Zeitwerk) starts, as in the test image.
      # Checked in new processes, as at start-up.
      class NamespaceTest < ActiveSupport::TestCase
        def rails(*)
          out, status = Open3.capture2e({ 'RAILS_ENV' => 'test' }, 'bin/rails', *, chdir: Rails.root.to_s)
          assert status.success?, out
          out
        end

        # RedmineKit is the namespace of every plugin of the organization; the
        # code loader makes it from their lib/redmine_kit/ directories. A plugin
        # with lib/redmine_kit.rb would own it.
        def test_no_plugin_file_defines_redmine_kit
          dir = Redmine::Plugin.find(:redmine_kit_aws_ses).directory

          assert_not File.exist?(File.join(dir, 'lib/redmine_kit.rb')), 'lib/redmine_kit.rb defines RedmineKit'
        end

        def test_zeitwerk_loads_every_file
          assert_includes rails('zeitwerk:check'), 'All is good!'
        end

        def test_both_plugins_start_with_the_boot_file_loaded
          script = 'print RedmineKit::Aws::VERSION, " ", RedmineKit::Aws::Ses::VERSION, " ", ' \
                   'RedmineKit::Aws::Admin.tabs.map(&:name).join(","), " ", RedmineKit::Aws::Ses::Receiver.name'

          assert_equal "#{RedmineKit::Aws::VERSION} #{VERSION} status,mail_sending,mail_receiving RedmineKit::Aws::Ses::Receiver",
                       rails('runner', script).lines.last.to_s.strip
        end
      end
    end
  end
end
