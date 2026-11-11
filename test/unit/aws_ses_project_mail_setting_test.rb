# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    class AwsSesProjectMailSettingTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper

      def test_address
        with_ses_settings do
          assert_equal "ecookbook@#{DOMAIN}", AwsSesProjectMailSetting.address_for(Project.find(1))
          assert_equal "ecookbook@#{DOMAIN}", AwsSesProjectMailSetting.new(project: Project.find(1)).address
        end
      end

      # An identifier that does not fit before @, a role address or the default
      # address is no project's address.
      def test_identifiers_that_cannot_be_an_address
        with_ses_settings do
          assert_nil AwsSesProjectMailSetting.address_for(Project.generate!(identifier: 'a' * 65))
          assert_equal "#{'a' * 64}@#{DOMAIN}",
                       AwsSesProjectMailSetting.address_for(Project.generate!(identifier: 'a' * 64))
          assert_nil AwsSesProjectMailSetting.address_for(Project.generate!(identifier: 'postmaster'))
          assert_nil AwsSesProjectMailSetting.address_for(Project.generate!(identifier: 'noreply'))
        end
        with_ses_settings('global_local_part' => 'helpdesk') do
          assert_nil AwsSesProjectMailSetting.address_for(Project.generate!(identifier: 'helpdesk'))
        end
      end

      def test_issue_defaults_are_names
        s = AwsSesProjectMailSetting.new(project: Project.find(1), tracker_id: 2, priority_id: 6,
                                         assigned_to_id: 2, is_private: true)

        assert_equal({ tracker: 'Feature request', priority: 'High', assigned_to: 'jsmith', is_private: '1' },
                     s.issue_defaults)
      end

      # The defaults can only be the project's trackers and categories, an
      # active priority and a user the project's issues can be assigned to.
      def test_defaults_are_the_choices_of_the_project
        other_tracker = Tracker.generate!
        { tracker_id: [2, other_tracker.id], category_id: [1, 3], priority_id: [6, 15],
          assigned_to_id: [2, 4] }.each do |attribute, (allowed, refused)|
          setting = AwsSesProjectMailSetting.new(project: Project.find(1), attribute => allowed)

          assert_predicate setting, :valid?, attribute
          setting = AwsSesProjectMailSetting.new(project: Project.find(1), attribute => refused)

          assert_not setting.valid?, attribute
          assert_includes setting.errors.details[attribute], { error: :inclusion }, attribute
        end
      end

      def test_a_saved_default_that_is_no_longer_a_choice_does_not_stop_other_changes
        setting = AwsSesProjectMailSetting.create!(project: Project.find(1), tracker_id: 3)
        Project.find(1).trackers.delete(Tracker.find(3))
        setting.reload.receive = true

        assert setting.save
      end

      # "create" makes Redmine create users, which only administrators do.
      def test_only_administrators_choose_to_create_users
        admin = User.find(1)
        manager = User.find(2)
        setting = AwsSesProjectMailSetting.new(project: Project.find(1))
        setting.send(:safe_attributes=, { 'unknown_user' => 'create' }, manager)

        assert_not setting.valid?
        assert_equal %w[ignore accept], setting.unknown_user_values(manager)
        setting.send(:safe_attributes=, { 'unknown_user' => 'create' }, admin)

        assert setting.save
        assert_equal %w[ignore accept create], setting.reload.unknown_user_values(manager)
        setting.send(:safe_attributes=, { 'receive' => '1' }, manager)

        assert setting.save, 'a value an administrator chose stays'
        setting.send(:safe_attributes=, { 'unknown_user' => 'accept' }, manager)

        assert setting.save
        setting.send(:safe_attributes=, { 'unknown_user' => 'create' }, manager)

        assert_not setting.save
      end

      def test_deleting_the_project_deletes_its_settings
        project = Project.generate!
        AwsSesProjectMailSetting.create!(project: project, receive: true)
        project.reload.destroy

        assert_not AwsSesProjectMailSetting.exists?(project_id: project.id)
      end
    end
  end
end
