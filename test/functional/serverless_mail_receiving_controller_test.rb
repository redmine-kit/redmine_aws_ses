# frozen_string_literal: true

require_relative '../test_helper'

module RedmineServerlessSes
  class ServerlessMailReceivingControllerTest < Redmine::ControllerTest
    include RedmineServerlessSes::TestHelper
    include ActiveJob::TestHelper

    tests ServerlessMailReceivingController

    def setup
      @request.session[:user_id] = 1
      Resolv::DNS.any_instance.stubs(:getresources).returns([])
    end

    def test_index
      ServerlessReceivedMail.create!(message_id: 'm1', status: 'imported', mail_from: 'jsmith@somenet.foo',
                                     subject: 'Hello', project_id: 1)
      ServerlessReceivedMail.create!(message_id: 'm2', status: 'dropped', reason: 'dmarc', subject: 'Forged')
      with_ses_settings { get :index }

      assert_response :success
      assert_select 'table.serverless-mail-addresses td', text: "redmine@#{DOMAIN}"
      assert_select '#serverless-received-mails tbody tr', 2
      assert_select '#serverless-received-mails tr.dropped', text: /DMARC/
      assert_select 'input[type=checkbox][name=?]', 'settings[import_without_dmarc_pass]'
      assert_select 'input[type=checkbox][name=?]', 'settings[import_spam]'
      with_ses_settings { get :index, params: { dropped: '1' } }

      assert_select '#serverless-received-mails tbody tr', 1
    end

    def test_update_settings
      with_ses_settings do
        post :update, params: { settings: { global_local_part: 'NoReply', global_mail: 'default_project',
                                            default_project: 'ecookbook', per_project_addresses: '1',
                                            project_senders: '0', import_without_dmarc_pass: '1',
                                            import_spam: '0' } }

        assert_redirected_to '/admin/serverless/mail_receiving'
        assert_equal 'noreply', RedmineServerlessSes.settings['global_local_part']
        assert RedmineServerlessSes.per_project_addresses?
        assert_equal %w[1 0], RedmineServerlessSes.settings.values_at('import_without_dmarc_pass', 'import_spam')
      end
    end

    def test_update_refuses_a_bad_address
      with_ses_settings do
        post :update, params: { settings: { global_local_part: 'a b' } }

        assert_equal 'redmine', RedmineServerlessSes.settings['global_local_part']
      end
    end

    def test_reimport_enqueues_jobs
      mail = ServerlessReceivedMail.create!(message_id: 'm1', status: 'dropped', reason: 'import_error')
      with_test_adapter do
        assert_enqueued_with(job: ServerlessReimportMailJob, args: ['m1']) do
          post :reimport, params: { ids: [mail.id] }
        end
      end
      assert_redirected_to '/admin/serverless/mail_receiving'
    end

    def test_non_administrators_are_refused
      @request.session[:user_id] = 2
      get :index

      assert_response :forbidden
    end
  end
end
