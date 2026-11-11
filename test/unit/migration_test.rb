# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # The migrations use the migration class of the Rails version that
    # Redmine runs on (Redmine 7.0: Rails 8.1), as Redmine's own do.
    class MigrationTest < ActiveSupport::TestCase
      def test_the_migration_class_of_redmine
        files = Dir[File.expand_path('../../db/migrate/*.rb', __dir__)]

        assert_not_empty files
        files.each do |file|
          require file
          migration = File.basename(file, '.rb').sub(/\A\d+_/, '').camelize.constantize

          assert_equal ActiveRecord::Migration[ActiveRecord::Migration.current_version], migration.superclass, file
        end
      end
    end
  end
end
