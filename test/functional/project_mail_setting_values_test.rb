# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # Values of the "Email" tab of project settings: the forwarding settings
    # and parameters of unexpected shapes.
    class ProjectMailSettingValuesTest < Redmine::ControllerTest
      include RedmineAws::SES::TestHelper

      tests AwsSesProjectMailSettingsController

      def setup
        Role.find(1).add_permission! :manage_aws_ses_mail_settings
        @request.session[:user_id] = 2
      end

      def test_forwarding_settings_by_an_administrator
        @request.session[:user_id] = 1
        patch_setting(forwarders: "Support@Company.example\r\n", import_forwarded: '1', forwarded_author: 'registered')

        assert_redirected_to '/projects/ecookbook/settings/aws_ses_mail'
        setting = AwsSesProjectMailSetting.find_by(project_id: 1)

        assert_equal [%w[support@company.example], true, 'registered'],
                     [setting.forwarder_list, setting.import_forwarded?, setting.forwarded_author]
      end

      # Only administrators choose whose email is trusted and whose name an
      # issue carries; a member with the permission sees them disabled.
      def test_a_member_cannot_change_the_forwarding_settings
        patch_setting(forwarders: 'company.example', import_forwarded: '1', forwarded_author: 'registered',
                      receive: '1')
        setting = AwsSesProjectMailSetting.find_by(project_id: 1)

        assert_equal [true, [], false, 'external'],
                     [setting.receive?, setting.forwarder_list, setting.import_forwarded?, setting.forwarded_author]
      end

      def test_forwarders_that_are_not_addresses_or_domains
        @request.session[:user_id] = 1
        patch_setting(forwarders: 'not a domain')

        assert_response :success
        assert_select '#errorExplanation li', text: 'Forwarders is invalid'
        assert_select 'form#aws-ses-project-mail-setting textarea[name=?]', 'aws_ses_project_mail_setting[forwarders]'
        assert_nil AwsSesProjectMailSetting.find_by(project_id: 1)
      end

      # values => the saved attributes, or nil when nothing is saved.
      UNEXPECTED = [['a string', {}], [{ receive: ['1'], tracker_id: { id: '2' } },
                                       { 'receive' => false, 'tracker_id' => nil }],
                    [{ project_id: '2', receive: '1' }, { 'project_id' => 1, 'receive' => true }],
                    [{ forwarded_author: ['registered'] }, { 'forwarded_author' => 'external' }],
                    [{ category_id: '3' }, nil]].freeze

      # Each parameter of an unexpected shape is ignored, the others saved.
      def test_unexpected_parameters
        UNEXPECTED.each do |values, saved|
          AwsSesProjectMailSetting.delete_all
          patch_setting(values)

          assert_saved(saved, values)
        end
      end

      private

      def patch_setting(values)
        with_ses_settings('per_project_addresses' => '1') do
          patch :update, params: { project_id: 'ecookbook', aws_ses_project_mail_setting: values }
        end
      end

      def assert_saved(saved, values)
        setting = AwsSesProjectMailSetting.find_by(project_id: 1)
        return assert_nil(setting, values.inspect) unless saved

        assert_redirected_to '/projects/ecookbook/settings/aws_ses_mail'
        assert_equal saved, setting.attributes.slice(*saved.keys), values.inspect
        assert_not AwsSesProjectMailSetting.exists?(project_id: 2)
      end
    end
  end
end
