# frozen_string_literal: true

require_relative '../test_helper'

module RedmineKit
  module Aws
    module Ses
      # The email tabs and a project's Email tab in Redmine Kit's new UI
      # (redmine_kit_ui, installed by bin/test's first run): the manifest it
      # takes, and the JSON and actions of the browser's session (kit
      # requests: the session and the CSRF token), with SES stubbed as the
      # functional tests stub it.
      class KitTest < Redmine::IntegrationTest
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

        test 'redmine_kit_ui takes the manifest: two tabs of the page AWS and the project tab' do
          manifest = assert_kit_manifest(:redmine_kit_aws_ses)
          screens = manifest.screens.map { |s| s.values_at(:path, :component, :tab, :position) }
          assert_equal [['/admin/aws/mail_sending', 'AwsSesMailSending', 'label_aws_ses_mail_sending', 30],
                        ['/admin/aws/mail_receiving', 'AwsSesMailReceiving', 'label_aws_ses_mail_receiving', 40]],
                       screens
          assert_equal %w[AwsSesProjectMail], manifest.settings[:project].pluck(:component)
        end

        test 'the sending JSON: the state as the page formats it' do
          stub_ses_state
          with_ses_settings do
            AwsSesSnapshot.refresh!
            get '/admin/aws/mail_sending.json', headers: kit_session('admin', 'admin')
          end
          assert_response :success
          json = response.parsed_body
          assert_equal DOMAIN, json['domain']
          assert_includes json['account']['rows'], { 'name' => 'Daily sending quota', 'value' => '50,000' }
          suppressed = json['suppressed']['rows'].map { |row| row.slice('address', 'user', 'reason') }
          assert_equal [{ 'address' => 'jsmith@somenet.foo', 'user' => 'John Smith', 'reason' => 'Bounce' }], suppressed
        end

        test 'unsuppress: the notice; an error of SES is 422 with its class' do
          stub_ses_state
          headers = kit_session('admin', 'admin')
          with_ses_settings do
            AwsSesSnapshot.refresh!
            post '/admin/aws/mail_sending/unsuppress.json', params: { address: 'jsmith@somenet.foo' }, headers: headers,
                                                            as: :json
          end
          assert_response :success
          assert_equal 'jsmith@somenet.foo was removed from the suppression list.', response.parsed_body['notice']
          stub_ses(delete_suppressed_destination: 'AccessDeniedException')
          with_ses_settings do
            post '/admin/aws/mail_sending/unsuppress.json', params: { address: 'x@example.net' }, headers: headers,
                                                            as: :json
          end
          assert_response 422
          assert_match(/AccessDeniedException/, response.parsed_body['errors'].sole)
        end

        test 'the receiving JSON, the re-import and the settings with their errors' do
          mail = AwsSesReceivedMail.create!(message_id: 'm1', status: 'dropped', reason: 'import_error')
          headers = kit_session('admin', 'admin')
          with_ses_settings('per_project_addresses' => '1') do
            get '/admin/aws/mail_receiving.json', params: { dropped: '1' }, headers: headers
            json = response.parsed_body
            assert_equal [mail.id], json['received'].pluck('id')
            assert_equal "noreply@#{DOMAIN}", json['addresses'].detect { |r| r['name'] == 'Default address' }['value']
            assert_equal 'noreply', json['settings']['global_local_part']
            assert_includes json['default_projects'], { 'value' => 'ecookbook', 'label' => 'eCookbook' }

            with_test_adapter do
              post '/admin/aws/mail_receiving/reimport.json', params: { ids: [mail.id] }, headers: headers, as: :json
              assert_response :success
              assert_equal [['m1']], ActiveJob::Base.queue_adapter.enqueued_jobs.pluck(:args)
            end

            post '/admin/aws/mail_receiving.json', params: { settings: { global_local_part: 'Bad Name!' } },
                                                   headers: headers, as: :json
            assert_response 422
            assert_equal 1, response.parsed_body['errors'].size
            assert_equal 'noreply', Setting.plugin_redmine_kit_aws_ses['global_local_part']
            post '/admin/aws/mail_receiving.json', params: { settings: { global_local_part: 'help' } },
                                                   headers: headers, as: :json
            assert_response :success
            assert_equal 'help', Setting.plugin_redmine_kit_aws_ses['global_local_part']
          end
        end

        test 'the tabs are for system administrators, and the actions need the CSRF token' do
          headers = kit_session('jsmith')
          get '/admin/aws/mail_sending.json', headers: headers
          assert_response :forbidden
          get '/admin/aws/mail_receiving.json', headers: headers
          assert_response :forbidden
          reset!
          # Redmine's login form, as the other sign-ins: kit_session turned the protection on
          ActionController::Base.allow_forgery_protection = false
          headers = kit_session('admin', 'admin')
          post '/admin/aws/mail_receiving.json', params: { settings: { global_local_part: 'help' } },
                                                 headers: headers.except('X-CSRF-Token'), as: :json
          assert_response 422
          assert_not_equal 'help', Setting.plugin_redmine_kit_aws_ses['global_local_part']
        end
      end
    end
  end
end
