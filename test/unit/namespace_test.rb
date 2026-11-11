# frozen_string_literal: true

require_relative '../test_helper'
require 'open3'

module RedmineAws
  module SES
    # The plugin's code is under the RedmineAws namespace of redmine_aws
    # (lib/redmine_aws/ses.rb), and its boot file defines RedmineAws::SES::Boot
    # before Redmine's code loader (Zeitwerk) starts, as in the test image.
    # Checked in new processes, as at start-up.
    class NamespaceTest < ActiveSupport::TestCase
      def rails(*)
        out, status = Open3.capture2e({ 'RAILS_ENV' => 'test' }, 'bin/rails', *, chdir: Rails.root.to_s)
        assert status.success?, out
        out
      end

      def test_zeitwerk_loads_every_file
        assert_includes rails('zeitwerk:check'), 'All is good!'
      end

      def test_both_plugins_start_with_the_boot_file_loaded
        script = 'print RedmineAws::VERSION, " ", RedmineAws::SES::VERSION, " ", ' \
                 'RedmineAws::Admin.tabs.map(&:name).join(","), " ", RedmineAws::SES::Receiver.name'

        assert_equal "#{RedmineAws::VERSION} #{VERSION} status,mail_sending,mail_receiving RedmineAws::SES::Receiver",
                     rails('runner', script).lines.last.to_s.strip
      end
    end
  end
end
