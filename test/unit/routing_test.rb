# frozen_string_literal: true

require_relative '../test_helper'

module RedmineServerlessSes
  class RoutingTest < ActiveSupport::TestCase
    include RedmineServerlessSes::TestHelper

    def target(*recipients)
      RedmineServerlessSes::Routing.new.target(recipients)&.project&.identifier
    end

    def receive(project, **attributes)
      ServerlessProjectMailSetting.create!(project: Project.find(project), receive: true, **attributes)
    end

    def test_per_project_address
      with_ses_settings('per_project_addresses' => '1') do
        receive(1)

        assert_equal 'ecookbook', target("ecookbook@#{DOMAIN}")
        assert_equal 'ecookbook', target("EcookBook@#{DOMAIN.upcase}")
        assert_nil target("support@#{DOMAIN}")
      end
    end

    def test_identifiers_that_cannot_be_an_address_are_not_routed
      with_ses_settings('per_project_addresses' => '1') do
        long = Project.generate!(identifier: 'a' * 65)
        ServerlessProjectMailSetting.create!(project: long, receive: true)
        role = Project.generate!(identifier: 'postmaster')
        ServerlessProjectMailSetting.create!(project: role, receive: true)

        assert_nil target("#{'a' * 65}@#{DOMAIN}")
        assert_nil target("postmaster@#{DOMAIN}")
      end
    end

    def test_a_project_that_does_not_receive
      with_ses_settings('per_project_addresses' => '1') do
        ServerlessProjectMailSetting.create!(project: Project.find(1), receive: false)

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
