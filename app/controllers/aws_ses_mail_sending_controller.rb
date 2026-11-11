# frozen_string_literal: true

# The "Sending email" tab (docs/admin.md#sending-email): the SES account, the
# sender domain and the suppression list.
class AwsSesMailSendingController < ApplicationController
  include RedmineAws::AdminTab

  helper :aws_ses_mail

  def index
    ses = RedmineAws::SES::Account.new
    @domain = RedmineAws::SES.domain
    @account, @account_error = fetch { ses.account }
    @identity, @identity_error = fetch { @domain ? ses.identity(@domain) : nil }
    @suppressed, @suppressed_error = fetch { ses.suppressed }
  end

  def unsuppress
    address = params[:address].to_s
    RedmineAws::SES::Account.new.unsuppress(address)
    logger&.info "[redmine_aws_ses] #{User.current.login} removed #{address} from the suppression list"
    # Redmine shows flash messages as HTML (render_flash_messages), so values
    # in them are escaped, as Redmine's own controllers do.
    flash[:notice] = l(:notice_aws_ses_mail_unsuppressed, address: ERB::Util.h(address))
  rescue StandardError => e
    flash[:error] = ERB::Util.h(api_error(e))
  ensure
    redirect_to action: 'index'
  end

  private

  # Any StandardError, as redmine_aws's connection checks do: a call to SES
  # can fail with service, network, credential or region errors, which have
  # no common class, and one failing section must not keep the page from
  # opening. The page shows the code or the class only (api_error).
  def fetch
    [yield, nil]
  rescue StandardError => e
    [nil, api_error(e)]
  end

  # A short message for the page (the AWS error code, or the class), with the
  # details in the log.
  def api_error(error)
    logger&.error "[redmine_aws_ses] #{error.class}: #{error.message}"
    l(:text_aws_ses_mail_api_error,
      error: error.respond_to?(:code) && error.code.present? ? error.code : error.class.name)
  end
end
