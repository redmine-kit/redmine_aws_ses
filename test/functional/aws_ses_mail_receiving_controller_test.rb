# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    class AwsSesMailReceivingControllerTest < Redmine::ControllerTest
      include RedmineAws::SES::TestHelper
      include ActiveJob::TestHelper

      tests AwsSesMailReceivingController

      def setup
        @request.session[:user_id] = 1
        Resolv::DNS.any_instance.stubs(:getresources).returns([])
      end

      def test_index
        AwsSesReceivedMail.create!(message_id: 'm1', status: 'imported', mail_from: 'jsmith@somenet.foo',
                                   subject: 'Hello', project_id: 1)
        AwsSesReceivedMail.create!(message_id: 'm2', status: 'dropped', reason: 'dmarc', subject: 'Forged')
        with_ses_settings { get :index }

        assert_response :success
        assert_select 'h2', text: 'AWS'
        assert_select '.tabs a.selected', text: 'Email receiving'
        # The default address is noreply@ while its email is not fetched.
        assert_select 'div.box.tabular p', text: /Default address\s*noreply@#{Regexp.escape(DOMAIN)}/
        assert_select '#aws-ses-received-mails tbody tr', 2
        assert_select '#aws-ses-received-mails tr.dropped td.description', text: 'Not fetched (DMARC fail)'
        assert_select '#aws-ses-received-mails th.checkbox input.toggle-selection[type=checkbox]'
        assert_select 'a', text: 'Check all', count: 0
        assert_select '#aws-ses-mail-settings .box.tabular.settings label.block',
                      text: /Also fetch email failing DMARC/ do
          assert_select 'input[type=checkbox][name=?]', 'settings[import_without_dmarc_pass]'
        end
        assert_select '#aws-ses-mail-settings label.block', text: /Also fetch spam/ do
          assert_select 'input[type=checkbox][name=?]', 'settings[import_spam]'
        end
        with_ses_settings { get :index, params: { dropped: '1' } }

        assert_select '#aws-ses-received-mails tbody tr', 1
      end

      # The verdicts that did not pass, in short labels; never the raw values.
      def test_the_verdicts
        AwsSesReceivedMail.create!(message_id: 'm1', status: 'imported', subject: 'Clean',
                                   verdicts: { spam: 'PASS', virus: 'PASS', dmarc: 'PASS' })
        AwsSesReceivedMail.create!(message_id: 'm2', status: 'dropped', reason: 'spam', subject: 'Offer',
                                   verdicts: { spam: 'FAIL', virus: 'PASS', dmarc: 'GRAY' })
        with_ses_settings { get :index }

        assert_select '#aws-ses-received-mails tr', text: /Clean.*Passed/m
        assert_select '#aws-ses-received-mails tr', text: /Offer.*Spam, DMARC no policy/m
        assert_not_includes response.body, 'PASS'
        assert_select 'em.info', 0
        assert_select 'label[for=settings_global_mail]', text: 'Incoming emails'
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

      def test_update_refuses_a_bad_address
        with_ses_settings do
          post :update, params: { settings: { global_local_part: 'a b' } }

          assert_equal 'noreply', RedmineAws::SES.settings['global_local_part']
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

      def test_non_administrators_are_refused
        @request.session[:user_id] = 2
        get :index

        assert_response :forbidden
      end
    end
  end
end
