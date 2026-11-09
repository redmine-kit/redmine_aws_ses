# frozen_string_literal: true

require_relative '../test_helper'

module RedmineServerlessSes
  class ServerlessProjectMailSettingTest < ActiveSupport::TestCase
    include RedmineServerlessSes::TestHelper

    def setting(project_id, alias_name)
      ServerlessProjectMailSetting.new(project: Project.find(project_id), alias_name: alias_name)
    end

    def test_alias_rules
      with_ses_settings do
        assert_predicate setting(1, 'support'), :valid?
        assert_not setting(1, 'onlinestore').valid?, 'another project identifier'
        assert_not setting(1, 'postmaster').valid?, 'reserved'
        assert_not setting(1, 'redmine').valid?, 'the address for the whole Redmine'
        assert_not setting(1, 'with space').valid?, 'format'
        setting(2, 'help').save!

        assert_not setting(1, 'help').valid?, 'another alias'
        assert_equal 'support', setting(1, ' Support ').tap(&:valid?).alias_name
      end
    end

    def test_address
      with_ses_settings do
        assert_equal "ecookbook@#{DOMAIN}", ServerlessProjectMailSetting.address_for(Project.find(1))
        assert_equal "help@#{DOMAIN}", setting(1, 'help').address
      end
    end

    def test_issue_defaults_are_names
      s = ServerlessProjectMailSetting.new(project: Project.find(1), tracker_id: 2, priority_id: 6,
                                           assigned_to_id: 2, is_private: true)

      assert_equal({ tracker: 'Feature request', priority: 'High', assigned_to: 'jsmith', is_private: '1' },
                   s.issue_defaults)
    end

    def test_deleting_the_project_deletes_its_settings_and_frees_the_alias
      with_ses_settings do
        project = Project.generate!
        ServerlessProjectMailSetting.create!(project: project, receive: true, alias_name: 'helpdesk')
        project.reload.destroy

        assert_not ServerlessProjectMailSetting.exists?(project_id: project.id)
        assert_predicate setting(1, 'helpdesk'), :valid?
      end
    end
  end
end
