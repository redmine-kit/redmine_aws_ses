# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # The "Email" tab of project settings.
    class ProjectMailSettingsTest < Redmine::ControllerTest
      include RedmineAws::SES::TestHelper

      tests AwsSesProjectMailSettingsController

      def test_update_with_the_permission
        Role.find(1).add_permission! :manage_aws_ses_mail_settings
        @request.session[:user_id] = 2
        with_ses_settings('per_project_addresses' => '1') do
          patch :update, params: { project_id: 'ecookbook',
                                   aws_ses_project_mail_setting: { receive: '1', unknown_user: 'accept' } }
        end

        assert_redirected_to '/projects/ecookbook/settings/aws_ses_mail'
        setting = AwsSesProjectMailSetting.find_by(project_id: 1)

        assert setting.receive?
        assert_equal 'accept', setting.unknown_user
      end

      def test_an_unknown_user_option_that_does_not_exist_is_refused
        update_as(1, unknown_user: 'forward')

        assert_nil AwsSesProjectMailSetting.find_by(project_id: 1)
        # The form again with Redmine's error list, as after a failed save of
        # an issue category; no flash.
        assert_response :success
        assert_select '#errorExplanation li', text: /Unknown user is not included in the list/
        assert_select 'form#aws-ses-project-mail-setting select[name=?] option[value=create]',
                      'aws_ses_project_mail_setting[unknown_user]'
        assert_nil flash[:error]
      end

      def test_a_category_of_another_project_is_refused
        @request.session[:user_id] = 1
        with_ses_settings('per_project_addresses' => '1') do
          patch :update, params: { project_id: 'ecookbook', aws_ses_project_mail_setting: { category_id: '3' } }
        end

        assert_nil AwsSesProjectMailSetting.find_by(project_id: 1)
        assert_select '#errorExplanation li', text: 'Category is not included in the list'
      end

      def test_a_manager_cannot_choose_to_create_users
        Role.find(1).add_permission! :manage_aws_ses_mail_settings
        @request.session[:user_id] = 2
        with_ses_settings('per_project_addresses' => '1') do
          patch :update, params: { project_id: 'ecookbook', aws_ses_project_mail_setting: { unknown_user: 'create' } }
        end

        assert_nil AwsSesProjectMailSetting.find_by(project_id: 1)
        assert_select '#errorExplanation li', text: /Unknown user/
        assert_select 'select#aws_ses_project_mail_setting_unknown_user option', 2
      end

      def test_without_the_permission
        @request.session[:user_id] = 2
        patch :update, params: { project_id: 'ecookbook', aws_ses_project_mail_setting: { receive: '1' } }

        assert_response :forbidden
      end

      private

      def update_as(user_id, values)
        @request.session[:user_id] = user_id
        with_ses_settings('per_project_addresses' => '1') do
          patch :update, params: { project_id: 'ecookbook', aws_ses_project_mail_setting: values }
        end
      end
    end

    class ProjectSettingsTabTest < Redmine::ControllerTest
      include RedmineAws::SES::TestHelper

      tests ProjectsController

      def test_the_tab_is_shown_with_addresses_per_project
        @request.session[:user_id] = 1
        with_ses_settings('per_project_addresses' => '1') { get :settings, params: { id: 'ecookbook' } }

        assert_select '#tab-aws_ses_mail'
        with_ses_settings { get :settings, params: { id: 'ecookbook' } }

        assert_select '#tab-aws_ses_mail', 0
      end

      # The permission alone opens project settings, as Redmine's own
      # permissions for a settings tab do (projects: :settings).
      def test_the_permission_alone_opens_the_tab
        user = User.generate!
        User.add_to_project(user, Project.find(1), Role.generate!(permissions: [:manage_aws_ses_mail_settings]))
        @request.session[:user_id] = user.id
        with_ses_settings('per_project_addresses' => '1') do
          get :settings, params: { id: 'ecookbook', tab: 'aws_ses_mail' }
        end

        assert_response :success
        # The tabs of project settings (the main menu is a .tabs too).
        assert_select '.tabs a[id^="tab-"]', 1
        assert_select '#tab-aws_ses_mail.selected'
      end

      # Members with the permission see the forwarding settings disabled;
      # administrators change them.
      def test_the_forwarding_fields_are_for_administrators
        Role.find(1).add_permission! :manage_aws_ses_mail_settings
        { 2 => { minimum: 1 }, 1 => 0 }.each do |user_id, disabled|
          @request.session[:user_id] = user_id
          with_ses_settings('per_project_addresses' => '1') do
            get :settings, params: { id: 'ecookbook', tab: 'aws_ses_mail' }
          end

          %w[forwarders import_forwarded forwarded_author].each do |name|
            assert_select '[name=?][disabled=disabled]', "aws_ses_project_mail_setting[#{name}]", disabled
          end
        end
      end

      def test_an_identifier_longer_than_64_characters_cannot_receive
        @request.session[:user_id] = 1
        project = Project.generate!(identifier: 'a' * 65)
        with_ses_settings('per_project_addresses' => '1') do
          get :settings, params: { id: project.identifier, tab: 'aws_ses_mail' }
        end

        assert_select '#aws-ses-project-mail-setting p', text: /Email\s*-/
        assert_select '#aws_ses_project_mail_setting_receive[disabled=disabled]'
      end

      def test_a_project_address
        @request.session[:user_id] = 1
        with_ses_settings('per_project_addresses' => '1') do
          get :settings, params: { id: 'ecookbook', tab: 'aws_ses_mail' }
        end

        assert_select '#aws-ses-project-mail-setting p', text: /ecookbook@/
        assert_select '#aws_ses_project_mail_setting_receive:not([disabled])'
      end
    end
  end
end
