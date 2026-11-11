# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    class RoutingTest < ActiveSupport::TestCase
      include RedmineAws::SES::TestHelper

      def target(*recipients)
        RedmineAws::SES::Routing.new.target(recipients)&.project&.identifier
      end

      def receive(project, **attributes)
        AwsSesProjectMailSetting.create!(project: Project.find(project), receive: true, **attributes)
      end

      # Replies to notifications go to the emission address; when it is not
      # the default address, it takes email as the default address does.
      def test_the_emission_address_is_a_default_address
        with_ses_settings('global_mail' => 'default_project', 'default_project' => 'ecookbook') do
          assert_equal 'ecookbook', target("noreply@#{DOMAIN}")
          assert_equal 'ecookbook', target("redmine@#{DOMAIN}")
        end
      end

      def test_per_project_address
        with_ses_settings('per_project_addresses' => '1') do
          receive(1)

          assert_equal 'ecookbook', target("ecookbook@#{DOMAIN}")
          assert_equal 'ecookbook', target("EcookBook@#{DOMAIN.upcase}")
          assert_nil target("support@#{DOMAIN}")
        end
      end

      # A role address is a project's address when a project has the
      # identifier (the tab warns about it); the default address takes the
      # email sent to it.
      def test_long_identifiers_role_addresses_and_the_default_address
        with_ses_settings('per_project_addresses' => '1') do
          { 'a' * 65 => nil, 'postmaster' => 'postmaster', 'support' => 'support', 'noreply' => nil }.each do |id, to|
            AwsSesProjectMailSetting.create!(project: Project.generate!(identifier: id), receive: true)

            assert_equal [to], [target("#{id}@#{DOMAIN}")], id
          end
        end
      end

      def test_a_project_that_does_not_receive
        with_ses_settings('per_project_addresses' => '1') do
          AwsSesProjectMailSetting.create!(project: Project.find(1), receive: false)

          assert_nil target("ecookbook@#{DOMAIN}")
          assert_nil target("onlinestore@#{DOMAIN}")
        end
      end

      def test_the_first_recipient_that_matches
        with_ses_settings('per_project_addresses' => '1') do
          receive(2)

          assert_equal 'onlinestore', target('someone@other.example', "nobody@#{DOMAIN}", "onlinestore@#{DOMAIN}")
        end
      end

      def test_other_domains_are_ignored
        with_ses_settings('per_project_addresses' => '1') do
          receive(1)

          assert_nil target('ecookbook@other.example')
        end
      end

      def test_the_global_address
        with_ses_settings('global_mail' => 'drop') { assert_nil target("noreply@#{DOMAIN}") }
        with_ses_settings('global_mail' => 'default_project', 'default_project' => 'onlinestore') do
          assert_equal 'onlinestore', target("noreply@#{DOMAIN}")
        end
      end

      def test_subaddress_without_per_project_addresses
        with_ses_settings do
          assert_equal 'ecookbook', target("noreply+ecookbook@#{DOMAIN}")
          assert_nil target("ecookbook@#{DOMAIN}")
          assert_nil target("noreply+missing@#{DOMAIN}")
        end
      end
    end
  end
end
