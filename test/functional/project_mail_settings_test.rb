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
                                 serverless_project_mail_setting: { receive: '1', alias_name: 'support',
                                                                    unknown_user: 'accept' } }
      end

      assert_redirected_to '/projects/ecookbook/settings/serverless_mail'
      setting = ServerlessProjectMailSetting.find_by(project_id: 1)

      assert setting.receive?
      assert_equal %w[support accept], [setting.alias_name, setting.unknown_user]
    end

    def test_an_alias_in_use_is_refused
      @request.session[:user_id] = 1
      with_ses_settings('per_project_addresses' => '1') do
        patch :update, params: { project_id: 'ecookbook',
                                 serverless_project_mail_setting: { alias_name: 'onlinestore' } }
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
  end
end
