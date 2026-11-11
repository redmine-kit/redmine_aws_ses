# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # Refreshing the stored state and removing addresses from the suppression
    # list.
    class AwsSesMailSendingActionsTest < Redmine::ControllerTest
      include RedmineAws::SES::TestHelper

      tests AwsSesMailSendingController

      def setup
        @request.session[:user_id] = 1
        Resolv::DNS.any_instance.stubs(:getresources).returns([])
      end

      def test_refresh_stores_the_state
        stub_ses_state
        with_ses_settings do
          assert_difference('AwsSesSnapshot.count', 1) { post :refresh, params: { tab: 'mail_sending' } }
        end

        assert_redirected_to '/admin/aws/mail_sending'
        assert_equal 'HEALTHY', AwsSesSnapshot.latest.section(:account)['enforcement_status']
        with_ses_settings { post :refresh, params: { tab: 'mail_receiving' } }

        assert_redirected_to '/admin/aws/mail_receiving'
        assert_equal 1, AwsSesSnapshot.count, 'only the latest is kept'
      end

      # Only the tabs of the plugin: a value from the request never chooses
      # the path.
      def test_refresh_goes_back_to_an_email_tab_only
        stub_ses_state
        ['//evil.example', 'http://evil.example/', nil].each do |tab|
          with_ses_settings { post :refresh, params: { tab: tab }.compact }

          assert_redirected_to '/admin/aws/mail_sending'
        end
      end

      def test_unsuppress
        stored_state
        client = stub_ses
        log = capture_log(ActionController::Base) { post :unsuppress, params: { address: 'JSmith@somenet.foo' } }

        assert_redirected_to '/admin/aws/mail_sending'
        request = client.api_requests.find { |r| r[:operation_name] == :delete_suppressed_destination }

        assert_equal 'JSmith@somenet.foo', request[:params][:email_address]
        assert_empty AwsSesSnapshot.latest.suppressed, 'the stored list no longer has the address'
        assert_match(/admin removed JSmith@somenet\.foo from the suppression list/, log)
      end

      # Redmine shows the flash as HTML, so the address from the request is
      # escaped in it.
      def test_the_address_is_escaped_in_the_flash
        stub_ses
        post :unsuppress, params: { address: '<b>x</b>@example.net' }

        assert_equal '&lt;b&gt;x&lt;/b&gt;@example.net was removed from the suppression list.', flash[:notice]
      end

      def test_a_failed_removal_shows_the_error_class
        stub_ses(delete_suppressed_destination: 'NotFoundException')
        log = capture_log(ActionController::Base) { post :unsuppress, params: { address: 'jsmith@somenet.foo' } }

        assert_redirected_to '/admin/aws/mail_sending'
        assert_equal 'Could not call the SES API (Aws::SESV2::Errors::NotFoundException). See the log for details.',
                     flash[:error]
        assert_match(/NotFoundException: stubbed-response-error-message/, log)
      end

      def test_non_administrators_are_refused
        @request.session[:user_id] = 2
        get :index

        assert_response :forbidden
        %i[unsuppress refresh].each do |action|
          post action, params: { address: 'a@b.example' }

          assert_response :forbidden
        end
      end

      private

      def stored_state
        stub_ses_state
        with_ses_settings { AwsSesSnapshot.refresh! }
      end
    end
  end
end
