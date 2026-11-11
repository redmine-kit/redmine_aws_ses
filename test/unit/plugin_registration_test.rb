# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # Without redmine_aws, Redmine says which plugin is missing
    # (Redmine::PluginRequirementError) before anything in the register block
    # uses it: requires_redmine_plugin comes first.
    class PluginRegistrationTest < ActiveSupport::TestCase
      def test_redmine_aws_is_required_first
        init = File.read(File.expand_path('../../init.rb', __dir__))
        block = init[/Redmine::Plugin\.register :redmine_aws_ses do\n(.*?)\nend/m, 1]
        first = block.lines.map(&:strip).reject { |line| line.empty? || line.start_with?('#') }.first

        assert_equal "requires_redmine_plugin :redmine_aws, version_or_higher: '0.1.0'", first
        assert_equal 1, init.scan('requires_redmine_plugin').size
      end
    end
  end
end
