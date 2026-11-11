# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    class AwsSesMailSendingControllerTest < Redmine::ControllerTest
      include RedmineAws::SES::TestHelper

      tests AwsSesMailSendingController

      def setup
        @request.session[:user_id] = 1
        Rails.cache.clear
      end

      def stub_all
        quota = { max_24_hour_send: 50_000.0, max_send_rate: 14.0, sent_last_24_hours: 12.0 }
        stub_ses(get_account: { production_access_enabled: true, sending_enabled: true, enforcement_status: 'HEALTHY',
                                send_quota: quota },
                 get_email_identity: { verified_for_sending_status: true, dkim_attributes: { status: 'SUCCESS' } },
                 list_suppressed_destinations: { suppressed_destination_summaries: [
                   { email_address: 'jsmith@somenet.foo', reason: 'BOUNCE', last_update_time: Time.current }
                 ] })
      end

      def test_index_shows_the_account_and_the_suppression_list
        stub_all
        with_ses_settings { get :index }

        assert_response :success
        assert_select 'div.flash.error', 0, response.body[%r{<div class="flash error">.*?</div>}m]
        assert_select 'div.box.tabular p', text: /Account status\s*Healthy/
        assert_select 'div.box.tabular p', text: /Sending\s*Enabled/
        assert_select 'div.box.tabular p', text: /Daily sending quota\s*50,000/
        assert_select 'div.box.tabular p', text: /Sent in the last 24 hours\s*12/
        assert_select 'div.box.tabular p', text: /Maximum send rate\s*14 per second/
        assert_select 'div.box.tabular p', text: /DKIM\s*Successful/
        assert_select 'table.list.suppressed tr', text: /jsmith@somenet\.foo\s*John Smith\s*Bounce/
        assert_select 'table.list.suppressed td.buttons a.icon-del', text: 'Remove'
        assert_not_includes response.body, 'HEALTHY'
        assert_select 'p', text: /SES does not send/, count: 0
        assert_select 'p a.icon.icon-email[data-method=post][href=?]', '/admin/test_email'
      end

      # Redmine keeps addresses as they were typed and matches them without
      # case.
      def test_the_user_of_an_address_typed_in_another_case
        EmailAddress.find_by(address: 'jsmith@somenet.foo').update_column(:address, 'JSmith@Somenet.foo')
        stub_all
        with_ses_settings { get :index }

        assert_select 'table.list.suppressed tr', text: /jsmith@somenet\.foo\s*John Smith/
      end

      def test_the_tab_is_on_the_aws_page
        stub_all
        with_ses_settings { get :index }

        # The tab of the "AWS" page of redmine_aws, with its menu item selected.
        assert_select 'h2', text: 'AWS'
        assert_select '.tabs a.selected', text: 'Email sending'
        assert_select '.tabs a', text: 'Email receiving'
        assert_select '#admin-menu a.selected', text: /AWS/
      end

      def test_index_opens_when_ses_fails
        stub_ses(get_account: 'AccessDeniedException', get_email_identity: 'NotFoundException',
                 list_suppressed_destinations: 'AccessDeniedException')
        with_ses_settings { get :index }

        assert_response :success
        assert_select 'div.flash.error', 3
        assert_select 'div.flash.error',
                      text: 'Could not call the SES API (AccessDeniedException). See the log for details.'
        assert_select 'div.flash.error', text: /NotFoundException/
        assert_not_includes response.body, 'stubbed response error', 'the raw exception message stays in the log'
      end

      def test_unsuppress
        client = stub_ses
        io = StringIO.new
        saved = ActionController::Base.logger
        ActionController::Base.logger = Logger.new(io)
        post :unsuppress, params: { address: 'jsmith@somenet.foo' }

        assert_redirected_to '/admin/aws/mail_sending'
        request = client.api_requests.find { |r| r[:operation_name] == :delete_suppressed_destination }

        assert_equal 'jsmith@somenet.foo', request[:params][:email_address]
        assert_match(/admin removed jsmith@somenet\.foo from the suppression list/, io.string)
      ensure
        ActionController::Base.logger = saved
      end

      # Redmine shows the flash as HTML, so the address from the request is
      # escaped in it.
      def test_the_address_is_escaped_in_the_flash
        stub_ses
        post :unsuppress, params: { address: '<b>x</b>@example.net' }

        assert_equal '&lt;b&gt;x&lt;/b&gt;@example.net was removed from the suppression list.', flash[:notice]
      end

      def test_a_failed_removal_shows_the_error_code
        stub_ses(delete_suppressed_destination: 'NotFoundException')
        post :unsuppress, params: { address: 'jsmith@somenet.foo' }

        assert_redirected_to '/admin/aws/mail_sending'
        assert_equal 'Could not call the SES API (NotFoundException). See the log for details.', flash[:error]
      end

      def test_non_administrators_are_refused
        @request.session[:user_id] = 2
        get :index

        assert_response :forbidden
        post :unsuppress, params: { address: 'a@b.example' }

        assert_response :forbidden
      end
    end
  end
end
