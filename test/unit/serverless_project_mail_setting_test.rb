# frozen_string_literal: true

require_relative '../test_helper'

module RedmineServerlessSes
  class ServerlessProjectMailSettingTest < ActiveSupport::TestCase
    include RedmineServerlessSes::TestHelper

    def test_address
      with_ses_settings do
        assert_equal "ecookbook@#{DOMAIN}", ServerlessProjectMailSetting.address_for(Project.find(1))
        assert_equal "ecookbook@#{DOMAIN}", ServerlessProjectMailSetting.new(project: Project.find(1)).address
      end
    end

    # An identifier that does not fit before @, a role address or the default
    # address is no project's address.
    def test_identifiers_that_cannot_be_an_address
      with_ses_settings do
        assert_nil ServerlessProjectMailSetting.address_for(Project.generate!(identifier: 'a' * 65))
        assert_equal "#{'a' * 64}@#{DOMAIN}",
                     ServerlessProjectMailSetting.address_for(Project.generate!(identifier: 'a' * 64))
        assert_nil ServerlessProjectMailSetting.address_for(Project.generate!(identifier: 'postmaster'))
        assert_nil ServerlessProjectMailSetting.address_for(Project.generate!(identifier: 'noreply'))
      end
      with_ses_settings('global_local_part' => 'helpdesk') do
        assert_nil ServerlessProjectMailSetting.address_for(Project.generate!(identifier: 'helpdesk'))
      end
    end

    def test_issue_defaults_are_names
      s = ServerlessProjectMailSetting.new(project: Project.find(1), tracker_id: 2, priority_id: 6,
                                           assigned_to_id: 2, is_private: true)

      assert_equal({ tracker: 'Feature request', priority: 'High', assigned_to: 'jsmith', is_private: '1' },
                   s.issue_defaults)
    end

    def test_deleting_the_project_deletes_its_settings
      project = Project.generate!
      ServerlessProjectMailSetting.create!(project: project, receive: true)
      project.reload.destroy

      assert_not ServerlessProjectMailSetting.exists?(project_id: project.id)
    end
  end
end
