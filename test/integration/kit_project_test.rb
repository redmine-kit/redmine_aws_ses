# frozen_string_literal: true

require_relative '../test_helper'

module RedmineKit
  module Aws
    module Ses
      # A project's Email tab in Redmine Kit's new UI (redmine_kit_ui,
      # installed by bin/test's first run): its JSON of the browser's session
      # (kit requests), with the tab's permission and only while addresses per
      # project are on.
      class KitProjectTest < Redmine::IntegrationTest
        include RedmineKit::Aws::Ses::TestHelper
        include RedmineKit::Ui::TestHelper if Redmine::Plugin.installed?(:redmine_kit_ui)

        fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :trackers,
                 :projects_trackers, :enabled_modules, :enumerations, :issue_categories

        def setup
          skip 'redmine_kit_ui is not installed (bin/test runs these with it)' unless kit_ui?
          User.current = nil
          Resolv::DNS.any_instance.stubs(:getresources).returns([])
        end

        def teardown
          ActionController::Base.allow_forgery_protection = false
        end

        def kit_ui?
          Redmine::Plugin.installed?(:redmine_kit_ui)
        end

        test "a project's tab: its values, and a manager can't change the forwarded email's" do
          Role.find(1).add_permission!(:manage_aws_ses_mail_settings)
          headers = kit_session('jsmith')
          with_ses_settings('per_project_addresses' => '1') do
            get '/projects/ecookbook/aws_ses_mail_setting.json', headers: headers
            assert_response :success
            json = response.parsed_body
            assert_equal "ecookbook@#{DOMAIN}", json['address']
            assert_not_includes json['editable'], 'forwarders'
            body = { aws_ses_project_mail_setting: { tracker_id: '2', forwarders: 'evil.example' } }
            patch '/projects/ecookbook/aws_ses_mail_setting.json', params: body, headers: headers, as: :json
            assert_response :success
            setting = AwsSesProjectMailSetting.find_by(project_id: 1)
            assert_equal [2, nil], [setting.tracker_id, setting.forwarders.presence]
          end
        end

        test "a project's tab is there only while addresses per project are on, and with the permission" do
          Role.find(1).add_permission!(:manage_aws_ses_mail_settings)
          headers = kit_session('jsmith')
          with_ses_settings { get '/projects/ecookbook/aws_ses_mail_setting.json', headers: headers }
          assert_response :not_found
          Role.find(1).remove_permission!(:manage_aws_ses_mail_settings)
          with_ses_settings('per_project_addresses' => '1') do
            get '/projects/ecookbook/aws_ses_mail_setting.json', headers: headers
          end
          assert_response :forbidden
        end
      end
    end
  end
end
