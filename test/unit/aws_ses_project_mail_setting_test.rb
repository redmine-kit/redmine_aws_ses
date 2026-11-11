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

      # Only an identifier that does not fit before @ is no project's address.
      def test_identifiers_that_cannot_be_an_address
        with_ses_settings do
          assert_nil AwsSesProjectMailSetting.address_for(Project.generate!(identifier: 'a' * 65))
          assert_equal "#{'a' * 64}@#{DOMAIN}",
                       AwsSesProjectMailSetting.address_for(Project.generate!(identifier: 'a' * 64))
        end
      end

      # Role addresses and the default address are addresses, which the
      # "Email receiving" tab warns about.
      # identifier => [role address?, default address?], with the default
      # address helpdesk@.
      ADDRESS_KINDS = { 'postmaster' => [true, false], 'support' => [true, false], 'helpdesk' => [false, true],
                        'noreply' => [true, false], 'kitchen' => [false, false] }.freeze

      def test_role_addresses_and_the_default_address
        with_ses_settings('global_local_part' => 'helpdesk') do
          ADDRESS_KINDS.each do |identifier, expected|
            setting = AwsSesProjectMailSetting.new(project: Project.generate!(identifier: identifier))

            assert_equal "#{identifier}@#{DOMAIN}", setting.address
            assert_equal expected, [setting.role_address?, setting.default_address?], identifier
          end
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
        setting = AwsSesProjectMailSetting.new(project: Project.find(1))

        assert_not set_values(setting, User.find(2), 'unknown_user' => 'create').valid?
        assert_equal %w[ignore accept], setting.unknown_user_values(User.find(2))
        assert set_values(setting, User.find(1), 'unknown_user' => 'create').save
      end

      def test_a_value_an_administrator_chose_stays
        setting = set_values(AwsSesProjectMailSetting.new(project: Project.find(1)), User.find(1),
                             'unknown_user' => 'create')
        setting.save!
        manager = User.find(2)

        assert_equal %w[ignore accept create], setting.reload.unknown_user_values(manager)
        assert set_values(setting, manager, 'receive' => '1').save
      end

      def test_a_member_cannot_choose_create_again
        setting = AwsSesProjectMailSetting.create!(project: Project.find(1), unknown_user: 'create')
        manager = User.find(2)

        assert set_values(setting, manager, 'unknown_user' => 'accept').save
        assert_not set_values(setting, manager, 'unknown_user' => 'create').save
      end

      def test_deleting_the_project_deletes_its_settings
        project = Project.generate!
        AwsSesProjectMailSetting.create!(project: project, receive: true)
        project.reload.destroy

        assert_not AwsSesProjectMailSetting.exists?(project_id: project.id)
      end

      private

      def set_values(setting, user, values)
        setting.send(:safe_attributes=, values, user)
        setting
      end
    end
  end
end
