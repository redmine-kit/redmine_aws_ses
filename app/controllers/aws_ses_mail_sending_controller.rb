# frozen_string_literal: true

# The "Sending email" tab (docs/admin.md#sending-email): the SES account, the
# sender domain and the suppression list, as the last refresh stored them
# (AwsSesSnapshot). The page itself never calls SES. Redmine's page (HTML,
# with redirects and flash messages), and the same data and actions as JSON
# for the new UI's tab (AwsSesMailSending of frontend/;
# AwsSesMailHelper#aws_ses_mail_sending_json).
class AwsSesMailSendingController < ApplicationController
  include RedmineKit::Aws::AdminTab

  helper :aws_ses_mail
  helper :aws_ses_mail_json

  def index
    @domain = RedmineKit::Aws::Ses.domain
    @snapshot = AwsSesSnapshot.latest
    respond_to do |format|
      format.html
      format.json { render json: view_context.aws_ses_mail_sending_json }
    end
  end

  # Reads the state of SES and DNS again, for both email tabs; back to the
  # tab the link was on. Each section's errors are kept in the state; an
  # error before any section is read (the SES client cannot be built, for
  # example without a region) is shown by its class, as unsuppress does.
  def refresh
    AwsSesSnapshot.refresh!
    logger&.info "[redmine_kit_aws_ses] #{User.current.login} refreshed the SES state"
    done(nil, tab_path)
  rescue StandardError => e
    logger&.error "[redmine_kit_aws_ses] could not refresh the SES state: #{e.class}: #{e.message}"
    failed(l(:text_aws_ses_mail_api_error, error: e.class.name), tab_path)
  end

  def unsuppress
    address = params[:address].to_s
    remove_suppressed(address)
  rescue StandardError => e
    # Any StandardError, as in Account#state. The class only on the page; the
    # message in the log.
    logger&.error "[redmine_kit_aws_ses] could not remove #{address} from the suppression list: " \
                  "#{e.class}: #{e.message}"
    failed(l(:text_aws_ses_mail_api_error, error: e.class.name), { action: 'index' })
  end

  private

  # An action that worked: back to the tab with its notice, or the notice as
  # JSON (text: Redmine's flash, which is HTML, gets it escaped).
  def done(notice, path)
    respond_to do |format|
      format.html do
        flash[:notice] = ERB::Util.h(notice) if notice
        redirect_to path
      end
      format.json { render json: { notice: notice, errors: [] } }
    end
  end

  # An action that failed: back to the tab with the error, or 422.
  def failed(error, path)
    respond_to do |format|
      format.html do
        flash[:error] = error
        redirect_to path
      end
      format.json { render json: { errors: [error] }, status: :unprocessable_content }
    end
  end

  # The email tab the request came from; a value from the request never
  # chooses the path.
  def tab_path
    params[:tab] == 'mail_receiving' ? aws_ses_mail_receiving_path : aws_ses_mail_sending_path
  end

  # From SES's list, and from the stored one until the next refresh.
  def remove_suppressed(address)
    RedmineKit::Aws::Ses::Account.new.unsuppress(address)
    AwsSesSnapshot.latest&.remove_suppressed!(address)
    logger&.info "[redmine_kit_aws_ses] #{User.current.login} removed #{address} from the suppression list"
    # Redmine shows flash messages as HTML (render_flash_messages), so the
    # notice is escaped there (done), as Redmine's own controllers do.
    done(l(:notice_aws_ses_mail_unsuppressed, address: address), { action: 'index' })
  end
end
