# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # The receiving settings and fetching again on the "Email receiving" tab.
    class AwsSesMailReceivingActionsTest < Redmine::ControllerTest
      include RedmineAws::SES::TestHelper
      include ActiveJob::TestHelper

      tests AwsSesMailReceivingController

      def setup
        @request.session[:user_id] = 1
        Resolv::DNS.any_instance.stubs(:getresources).returns([])
      end

      def test_update_settings
        with_ses_settings do
          post :update, params: { settings: { global_local_part: 'HelpDesk', global_mail: 'default_project',
                                              default_project: 'ecookbook', per_project_addresses: '1',
                                              project_senders: '0', import_without_dmarc_pass: '1',
                                              import_spam: '0' } }

          assert_redirected_to '/admin/aws/mail_receiving'
          assert_equal 'helpdesk', RedmineAws::SES.settings['global_local_part']
          assert RedmineAws::SES.per_project_addresses?
          assert_equal %w[1 0], RedmineAws::SES.settings.values_at('import_without_dmarc_pass', 'import_spam')
        end
      end

      # The page again with Redmine's error list above the form and the values
      # given, as Redmine's settings do.
      def test_update_refuses_a_bad_address
        with_ses_settings do
          post :update, params: { settings: { global_local_part: 'a b', import_spam: '1' } }

          assert_equal 'noreply', RedmineAws::SES.settings['global_local_part']
          assert_equal '0', RedmineAws::SES.settings['import_spam']
        end
        assert_response :success
        assert_nil flash[:error]
        assert_select '#aws-ses-mail-settings #errorExplanation li', text: /may contain only lowercase letters/
        assert_select '#aws-ses-mail-settings input[name=?][value=?]', 'settings[global_local_part]', 'a b'
        assert_select '#aws-ses-mail-settings input[name=?][checked=checked]', 'settings[import_spam]'
      end

      # Parameters of an unexpected shape are ignored: nothing changes and
      # the page does not fail.
      def test_update_with_unexpected_parameters
        [{ settings: 'a string' }, { settings: { global_local_part: ['x'] } },
         { settings: { global_local_part: { a: 'x' }, import_spam: ['1'] } }, {}].each do |params|
          with_ses_settings do
            post :update, params: params

            assert_equal %w[noreply 0], RedmineAws::SES.settings.values_at('global_local_part', 'import_spam'),
                         params.inspect
          end
          assert_redirected_to '/admin/aws/mail_receiving'
        end
      end

      def test_reimport_with_unexpected_parameters
        AwsSesReceivedMail.create!(message_id: 'm1', status: 'dropped', reason: 'import_error')
        with_test_adapter do
          [{ ids: { a: '1' } }, { ids: [{ a: '1' }] }, { ids: '1' }, {}].each do |params|
            assert_no_enqueued_jobs { post :reimport, params: params }
            assert_response :not_found, params.inspect
          end
        end
      end

      def test_reimport_enqueues_jobs
        mail = AwsSesReceivedMail.create!(message_id: 'm1', status: 'dropped', reason: 'import_error')
        with_test_adapter do
          assert_enqueued_with(job: AwsSesReimportMailJob, args: ['m1']) do
            post :reimport, params: { ids: [mail.id] }
          end
        end
        assert_redirected_to '/admin/aws/mail_receiving'
      end
    end
  end
end
