# frozen_string_literal: true

# The "Sending email" tab (docs/admin.md#sending-email): the SES account, the
# sender domain and the suppression list, as the last refresh stored them
# (AwsSesSnapshot). The page itself never calls SES.
class AwsSesMailSendingController < ApplicationController
  include RedmineAws::AdminTab

  helper :aws_ses_mail

  def index
    @domain = RedmineAws::SES.domain
    @snapshot = AwsSesSnapshot.latest
  end

  # Reads the state of SES and DNS again, for both email tabs; back to the
  # tab the link was on.
  def refresh
    AwsSesSnapshot.refresh!
    logger&.info "[redmine_aws_ses] #{User.current.login} refreshed the SES state"
    redirect_to params[:tab] == 'mail_receiving' ? aws_ses_mail_receiving_path : aws_ses_mail_sending_path
  end

  def unsuppress
    address = params[:address].to_s
    remove_suppressed(address)
  rescue StandardError => e
    # Any StandardError, as in Account#state. The class only on the page; the
    # message in the log.
    logger&.error "[redmine_aws_ses] could not remove #{address} from the suppression list: #{e.class}: #{e.message}"
    flash[:error] = l(:text_aws_ses_mail_api_error, error: e.class.name)
  ensure
    redirect_to action: 'index'
  end

  private

  # From SES's list, and from the stored one until the next refresh.
  def remove_suppressed(address)
    RedmineAws::SES::Account.new.unsuppress(address)
    AwsSesSnapshot.latest&.remove_suppressed!(address)
    logger&.info "[redmine_aws_ses] #{User.current.login} removed #{address} from the suppression list"
    # Redmine shows flash messages as HTML (render_flash_messages), so values
    # in them are escaped, as Redmine's own controllers do.
    flash[:notice] = l(:notice_aws_ses_mail_unsuppressed, address: ERB::Util.h(address))
  end
end
