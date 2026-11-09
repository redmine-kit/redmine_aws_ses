# frozen_string_literal: true

require_relative '../test_helper'

module RedmineServerlessSes
  class ServerlessMailSendingControllerTest < Redmine::ControllerTest
    include RedmineServerlessSes::TestHelper

    tests ServerlessMailSendingController

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
      assert_select 'div.box.tabular p', text: %r{12 / 50000}
      assert_select 'div.box.tabular p', text: /DKIM\s*SUCCESS/
      assert_select 'table.list.suppressed tr', text: /jsmith@somenet\.foo\s*John Smith\s*BOUNCE/
      assert_select 'p a.icon.icon-email[data-method=post][href=?]', '/admin/test_email'
    end

    def test_index_opens_when_ses_fails
      stub_ses(get_account: 'AccessDeniedException', get_email_identity: 'NotFoundException',
               list_suppressed_destinations: 'AccessDeniedException')
      with_ses_settings { get :index }

      assert_response :success
      assert_select 'div.flash.error', 3
      assert_select 'div.flash.error', text: 'Could not call the SES API (AccessDeniedException). See the log for details.'
      assert_select 'div.flash.error', text: /NotFoundException/
      assert_not_includes response.body, 'stubbed response error', 'the raw exception message stays in the log'
    end

    def test_unsuppress
      client = stub_ses
      io = StringIO.new
      saved = ActionController::Base.logger
      ActionController::Base.logger = Logger.new(io)
      post :unsuppress, params: { address: 'jsmith@somenet.foo' }

      assert_redirected_to '/admin/serverless/mail_sending'
      request = client.api_requests.find { |r| r[:operation_name] == :delete_suppressed_destination }

      assert_equal 'jsmith@somenet.foo', request[:params][:email_address]
      assert_match(/admin removed jsmith@somenet\.foo from the suppression list/, io.string)
    ensure
      ActionController::Base.logger = saved
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
