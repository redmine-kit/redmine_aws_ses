# frozen_string_literal: true

# The "Sending email" tab (docs/admin.md#sending-email): the SES account, the
# sender domain and the suppression list.
class ServerlessMailSendingController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :serverless

  before_action :require_admin

  def index
    ses = RedmineServerlessSes::SesAccount.new
    @domain = RedmineServerlessSes.domain
    @account, @account_error = fetch { ses.account }
    @identity, @identity_error = fetch { @domain ? ses.identity(@domain) : nil }
    @suppressed, @suppressed_error = fetch { ses.suppressed }
  end

  def unsuppress
    address = params[:address].to_s
    RedmineServerlessSes::SesAccount.new.unsuppress(address)
    logger&.info "[redmine_serverless_ses] #{User.current.login} removed #{address} from the suppression list"
    flash[:notice] = l(:notice_serverless_mail_unsuppressed, address: address)
  rescue StandardError => e
    flash[:error] = api_error(e)
  ensure
    redirect_to action: 'index'
  end

  private

  def fetch
    [yield, nil]
  rescue StandardError => e
    [nil, api_error(e)]
  end

  # A short message for the page (the AWS error code, or the class), with the
  # details in the log.
  def api_error(error)
    logger&.error "[redmine_serverless_ses] #{error.class}: #{error.message}"
    l(:text_serverless_mail_api_error, error: error.respond_to?(:code) && error.code.present? ? error.code : error.class.name)
  end
end
