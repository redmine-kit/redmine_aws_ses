# frozen_string_literal: true

require 'resolv'

# The "Receiving email" tab (docs/admin.md#receiving-email): addresses, the MX
# record, received email, re-importing and the receiving settings.
class ServerlessMailReceivingController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :serverless

  before_action :require_admin

  MX_TIMEOUT = 2

  def index
    @settings = RedmineServerlessSes.settings
    @domain = RedmineServerlessSes.domain
    @mx = mx_records if @domain
    @project_settings = ServerlessProjectMailSetting.includes(:project).order(:id).to_a
    scope = ServerlessReceivedMail.includes(:project).order(created_at: :desc)
    scope = scope.where(status: 'dropped') if params[:dropped] == '1'
    @received = scope.limit(100).to_a
  end

  def update
    values = params.require(:settings).permit(*RedmineServerlessSes::DEFAULTS.keys).to_h
    values['global_local_part'] = values['global_local_part'].to_s.strip.downcase
    unless values['global_local_part'].match?(ServerlessProjectMailSetting::LOCAL_PART)
      flash[:error] = l(:error_serverless_mail_local_part)
      return redirect_to(action: 'index')
    end

    Setting.plugin_redmine_serverless_ses = RedmineServerlessSes.settings.merge(values)
    audit('changed the receiving settings')
    flash[:notice] = l(:notice_successful_update)
    redirect_to action: 'index'
  end

  def reimport
    mails = ServerlessReceivedMail.where(id: Array(params[:ids]).map(&:to_i)).to_a
    return render_404 if mails.empty?

    mails.each { |mail| ServerlessReimportMailJob.perform_later(mail.message_id) }
    audit("re-imported #{mails.map(&:message_id).join(', ')}")
    flash[:notice] = l(:notice_serverless_mail_reimport, count: mails.size)
    redirect_to action: 'index'
  end

  private

  # The MX hosts of Redmine's domain, from DNS; nil when they cannot be read.
  def mx_records
    Rails.cache.fetch(['redmine_serverless_ses', 'mx', @domain], expires_in: 60) do
      Resolv::DNS.open do |dns|
        dns.timeouts = MX_TIMEOUT
        dns.getresources(@domain, Resolv::DNS::Resource::IN::MX).map { |mx| mx.exchange.to_s.downcase }.sort
      end
    end
  rescue StandardError
    nil
  end

  def audit(what)
    logger&.info "[redmine_serverless_ses] #{User.current.login} #{what}"
  end
end
