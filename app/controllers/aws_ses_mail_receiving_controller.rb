# frozen_string_literal: true

# The "Receiving email" tab (docs/admin.md#receiving-email): addresses, the MX
# record (as the last refresh stored it, AwsSesSnapshot), received email,
# re-importing and the receiving settings.
class AwsSesMailReceivingController < ApplicationController
  include RedmineAws::AdminTab

  helper :aws_ses_mail

  def index
    @settings ||= RedmineAws::SES.settings
    @domain = RedmineAws::SES.domain
    @snapshot = AwsSesSnapshot.latest
    @project_settings = AwsSesProjectMailSetting.includes(:project).order(:id).to_a
    @received = received_mails
  end

  # On an error, the page again with the values given and the error above
  # the form, as Redmine's settings do (SettingsController#edit).
  def update
    @settings = RedmineAws::SES.settings.merge(setting_params)
    unless @settings['global_local_part'].to_s.match?(AwsSesProjectMailSetting::LOCAL_PART)
      @setting_errors = [l(:error_aws_ses_mail_local_part)]
      index
      return render(:index)
    end

    Setting.plugin_redmine_aws_ses = @settings
    audit('changed the receiving settings')
    flash[:notice] = l(:notice_successful_update)
    redirect_to action: 'index'
  end

  def reimport
    mails = selected_mails
    return render_404 if mails.empty?

    mails.each { |mail| AwsSesReimportMailJob.perform_later(mail.message_id) }
    audit("re-imported #{mails.map(&:message_id).join(', ')}")
    flash[:notice] = l(:notice_aws_ses_mail_reimport, count: mails.size)
    redirect_to action: 'index'
  end

  private

  # The records of the ids[] of the form; anything else in ids finds
  # nothing.
  def selected_mails
    ids = params.slice(:ids).permit(ids: [])[:ids]
    AwsSesReceivedMail.where(id: Array(ids).map(&:to_i)).to_a
  end

  # The latest 100, or those not fetched.
  def received_mails
    scope = AwsSesReceivedMail.includes(:project).order(created_at: :desc)
    scope = scope.where(status: 'dropped') if params[:dropped] == '1'
    AwsSesReceivedMail.preload_issue_ids(scope.limit(100).to_a)
  end

  # The plugin's settings, each a single value; a parameter of another shape
  # is ignored.
  def setting_params
    values = params[:settings]
    values = values.is_a?(ActionController::Parameters) ? values.permit(*RedmineAws::SES::DEFAULTS.keys).to_h : {}
    values['global_local_part'] = values['global_local_part'].to_s.strip.downcase if values.key?('global_local_part')
    values
  end

  def audit(what)
    logger&.info "[redmine_aws_ses] #{User.current.login} #{what}"
  end
end
