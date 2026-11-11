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
        assert_select '.tabs a.selected', text: 'Email receiving'
        # The default address is noreply@ while its email is not fetched.
        assert_select 'table.list.values tr', text: /Default address\s*noreply@#{Regexp.escape(DOMAIN)}/
        assert_select '#aws-ses-received-mails tbody tr', 2
        assert_select '#aws-ses-received-mails tr.dropped td.description', text: 'Not fetched (DMARC fail)'
        assert_select '#aws-ses-received-mails th.checkbox input.toggle-selection[type=checkbox]'
      end

      def test_the_list_of_mail_not_fetched
        AwsSesReceivedMail.create!(message_id: 'm1', status: 'imported', subject: 'Hello')
        AwsSesReceivedMail.create!(message_id: 'm2', status: 'dropped', reason: 'dmarc', subject: 'Forged')
        with_ses_settings { get :index, params: { dropped: '1' } }

        assert_select '#aws-ses-received-mails tbody tr', 1
      end

      def test_the_receiving_settings_form
        with_ses_settings { get :index }

        assert_select 'a', text: 'Check all', count: 0
        { 'import_without_dmarc_pass' => /Also fetch email failing DMARC/, 'import_spam' => /Also fetch spam/ }
          .each do |name, text|
          assert_select '#aws-ses-mail-settings .box.tabular.settings label.block', text: text do
            assert_select 'input[type=checkbox][name=?]', "settings[#{name}]"
          end
        end
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

      def test_the_mx_record_before_the_first_refresh
        with_ses_settings { get :index }

        assert_select 'table.list.values tr', text: /MX\s*Unknown/
        assert_select '#aws-ses-mail-updated a[href=?]', '/admin/aws/mail_sending/refresh?tab=mail_receiving'
      end

      # The MX record as the last refresh read it; the page never asks DNS.
      def test_the_mx_record_is_the_stored_one
        Resolv::DNS.any_instance.stubs(:getresources).returns([stub(exchange: 'Inbound-SMTP.us-east-1.amazonaws.com')])
        stub_ses_state
        with_ses_settings { AwsSesSnapshot.refresh! }
        Resolv::DNS.any_instance.expects(:getresources).never
        with_ses_settings { get :index }

        assert_select 'table.list.values tr', text: /MX\s*inbound-smtp\.us-east-1\.amazonaws\.com/
        # Read for another domain: not this one's.
        with_settings(mail_from: 'redmine@other.example') { get :index }

        assert_select 'table.list.values tr', text: /MX\s*Unknown/
      end

      # Role addresses and the default address are allowed as project
      # addresses, with a warning.
      def test_warnings_about_project_addresses
        { 'support' => 1, 'noreply' => 2 }.each do |identifier, id|
          Project.find(id).update_column(:identifier, identifier)
          AwsSesProjectMailSetting.create!(project_id: id, receive: true)
        end
        with_ses_settings('per_project_addresses' => '1') { get :index }

        domain = Regexp.escape(DOMAIN)

        assert_select 'p.warning', text: /Role addresses are used as project addresses: support@#{domain}, noreply@/
        assert_select 'p.warning', text: /These project addresses are the default address: noreply@#{domain}\./
      end

      def test_a_warning_when_the_emission_address_is_not_the_default_address
        with_ses_settings { get :index }

        address = Regexp.escape("redmine@#{DOMAIN}")

        assert_select 'p.warning', text: /The emission email address \(#{address}\) is not the default/
        with_ses_settings('global_local_part' => 'redmine') { get :index }

        assert_select 'p.warning', text: /The emission email address/, count: 0
      end

      def test_no_warnings_for_projects_that_do_not_receive
        Project.find(1).update_column(:identifier, 'support')
        AwsSesProjectMailSetting.create!(project_id: 1, receive: false)
        with_ses_settings('per_project_addresses' => '1') { get :index }

        assert_select 'p.warning', text: /Role addresses are used|These project addresses are/, count: 0
      end

      def test_non_administrators_are_refused
        @request.session[:user_id] = 2
        get :index

        assert_response :forbidden
      end
    end
  end
end
