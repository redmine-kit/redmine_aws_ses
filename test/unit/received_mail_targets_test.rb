# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SES
    # What an import created: the list links issues (and the issues of
    # notes) only, and a second run of any of them imports nothing.
    class ReceivedMailTargetsTest < ActiveSupport::TestCase
      # target_type, target_id => issue_id
      TARGETS = { %w[Issue 1] => 1, %w[Journal 1] => 1, %w[Message 2] => nil, %w[Comment 1] => nil }.freeze

      def record(type, id)
        AwsSesReceivedMail.create!(message_id: "m-#{type}-#{id}", status: 'imported', target_type: type, target_id: id)
      end

      def test_only_issues_and_notes_have_an_issue
        records = TARGETS.keys.map { |type, id| record(type, id.to_i) }

        assert_equal(TARGETS.values, records.map { |r| AwsSesReceivedMail.find(r.id).issue_id })
        assert_equal TARGETS.values, AwsSesReceivedMail.preload_issue_ids(records).map(&:issue_id)
      end

      def test_what_still_exists_is_not_imported_again
        TARGETS.each_key do |type, id|
          assert_predicate record(type, id.to_i), :imported_target?, type
        end
        assert_not record('Message', 999).imported_target?
      end
    end
  end
end
