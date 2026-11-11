# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    class AwsSesMailSendingControllerTest < Redmine::ControllerTest
      include RedmineAws::SES::TestHelper

      tests AwsSesMailSendingController

      def setup
        @request.session[:user_id] = 1
        Resolv::DNS.any_instance.stubs(:getresources).returns([])
      end

      def test_index_shows_the_stored_state
        stored_state
        client = stub_ses
        with_ses_settings { get :index }

        assert_response :success
        assert_empty client.api_requests, 'the page never calls SES'
        assert_select 'div.flash.error', 0
        assert_select '#aws-ses-mail-updated', text: /Updated: .*Refresh/m
        [/Account status\s*Healthy/, /Daily sending quota\s*50,000/, /Maximum send rate\s*14 per second/,
         /DKIM\s*Successful/].each { |text| assert_select 'table.list.values tr', text: text }
      end

      def test_index_shows_the_stored_suppression_list
        stored_state
        with_ses_settings { get :index }

        assert_select 'table.list.suppressed tr', text: /jsmith@somenet\.foo\s*John Smith\s*Bounce/
        assert_not_includes response.body, 'HEALTHY'
        assert_select 'p a.icon.icon-email[data-method=post][href=?]', '/admin/test_email'
      end

      def test_index_before_the_first_refresh
        client = stub_ses
        with_ses_settings { get :index }

        assert_response :success
        assert_empty client.api_requests
        assert_select 'p.nodata', 3
        assert_select '#aws-ses-mail-updated', text: /\A\s*Refresh\s*\z/
        assert_select '#aws-ses-mail-updated a[data-method=post][href=?]',
                      '/admin/aws/mail_sending/refresh?tab=mail_sending'
      end

      def test_the_user_of_an_address_typed_in_another_case
        EmailAddress.find_by(address: 'jsmith@somenet.foo').update_column(:address, 'JSmith@Somenet.foo')
        stored_state
        with_ses_settings { get :index }

        assert_select 'table.list.suppressed tr', text: /jsmith@somenet\.foo\s*John Smith/
      end

      def test_the_tab_is_on_the_aws_page
        with_ses_settings { get :index }

        assert_select 'h2', text: 'AWS'
        assert_select '.tabs a.selected', text: 'Email sending'
        assert_select '.tabs a', text: 'Email receiving'
        assert_select '#admin-menu a.selected', text: /AWS/
      end

      # Each section on its own; the class of the error only, the message in
      # the log.
      def test_sections_that_failed_show_the_error_class
        stub_ses(get_account: 'AccessDeniedException', get_email_identity: 'NotFoundException',
                 list_suppressed_destinations: 'AccessDeniedException')
        log = capture_log { with_ses_settings { AwsSesSnapshot.refresh! } }
        with_ses_settings { get :index }

        assert_select 'div.flash.error', 3
        denied = 'Could not call the SES API (Aws::SESV2::Errors::AccessDeniedException). See the log for details.'

        assert_select 'div.flash.error', text: denied
        assert_select 'div.flash.error', text: /Aws::SESV2::Errors::NotFoundException/
        assert_not_includes response.body, 'stubbed-response-error-message'
        assert_match(/could not read the account section: Aws::SESV2::Errors::AccessDeniedException: stubbed/, log)
      end

      private

      def stored_state
        stub_ses_state
        with_ses_settings { AwsSesSnapshot.refresh! }
      end
    end
  end
end
