# frozen_string_literal: true

# Imports a received message again, from the "Receiving email" page. A job, so
# that the web requests need no permission to read the mail bucket or to call
# the task function (docs/admin.md#receiving-email).
class AwsSesReimportMailJob < ApplicationJob
  def perform(message_id)
    RedmineAws::SES::Receiver.new(message_id).run
  end
end
