# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # The plugin's tests run on an internal network (test/compose.yml): a
    # request that misses the test services fails instead of reaching AWS.
    # This fails if a connection to AWS opens.
    class NetworkTest < ActiveSupport::TestCase
      REGION = ENV.fetch('AWS_REGION', 'us-east-1')
      HOSTS = ["s3.#{REGION}.amazonaws.com", "email.#{REGION}.amazonaws.com", 'sts.amazonaws.com'].freeze

      def test_the_tests_cannot_reach_aws
        skip 'not on the network of bin/test' unless ENV['TEST_AWS_BACKEND'] == 'aws-emulator'

        HOSTS.each do |host|
          socket = Socket.tcp(host, 443, connect_timeout: 5)
          socket.close
          flunk "#{host}:443 is reachable from the tests"
        rescue SocketError, SystemCallError, IOError
          pass
        end
      end
    end
  end
end
