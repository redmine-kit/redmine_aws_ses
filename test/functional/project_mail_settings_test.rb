# frozen_string_literal: true

require_relative '../test_helper'

module RedmineServerlessSes
  # The "Email" tab of project settings.
  class ProjectMailSettingsTest < Redmine::ControllerTest
    include RedmineServerlessSes::TestHelper

    tests ServerlessProjectMailSettingsController

    def test_update_with_the_permission
      Role.find(1).add_permission! :manage_serverless_mail_settings
      @request.session[:user_id] = 2
      with_ses_settings('per_project_addresses' => '1') do
        patch :update, params: { project_id: 'ecookbook',
                                 serverless_project_mail_setting: { receive: '1', unknown_user: 'accept' } }
      end

      assert_redirected_to '/projects/ecookbook/settings/serverless_mail'
      setting = ServerlessProjectMailSetting.find_by(project_id: 1)

      assert setting.receive?
      assert_equal 'accept', setting.unknown_user
    end

    def test_an_unknown_user_option_that_does_not_exist_is_refused
      @request.session[:user_id] = 1
      with_ses_settings('per_project_addresses' => '1') do
        patch :update, params: { project_id: 'ecookbook',
                                 serverless_project_mail_setting: { unknown_user: 'forward' } }
      end

      assert_nil ServerlessProjectMailSetting.find_by(project_id: 1)
      assert_predicate flash[:error], :present?
    end

    def test_without_the_permission
      @request.session[:user_id] = 2
      patch :update, params: { project_id: 'ecookbook', serverless_project_mail_setting: { receive: '1' } }

      assert_response :forbidden
    end
  end

  class ProjectSettingsTabTest < Redmine::ControllerTest
    include RedmineServerlessSes::TestHelper

    tests ProjectsController

    def test_the_tab_is_shown_with_addresses_per_project
      @request.session[:user_id] = 1
      with_ses_settings('per_project_addresses' => '1') { get :settings, params: { id: 'ecookbook' } }

      assert_select '#tab-serverless_mail'
      with_ses_settings { get :settings, params: { id: 'ecookbook' } }

      assert_select '#tab-serverless_mail', 0
    end

    def test_an_identifier_longer_than_64_characters_cannot_receive
      @request.session[:user_id] = 1
      project = Project.generate!(identifier: 'a' * 65)
      with_ses_settings('per_project_addresses' => '1') do
        get :settings, params: { id: project.identifier, tab: 'serverless_mail' }
      end

      assert_select '#serverless-project-mail-setting p', text: /Email\s*-/
      assert_select '#serverless_project_mail_setting_receive[disabled=disabled]'
    end

    def test_a_project_address
      @request.session[:user_id] = 1
      with_ses_settings('per_project_addresses' => '1') do
        get :settings, params: { id: 'ecookbook', tab: 'serverless_mail' }
      end

      assert_select '#serverless-project-mail-setting p', text: /ecookbook@/
      assert_select '#serverless_project_mail_setting_receive:not([disabled])'
      assert_select '#serverless_project_mail_setting_alias_name', 0
    end
  end
end
