# frozen_string_literal: true

# The "Receiving email" tab (docs/admin.md#receiving-email): addresses, the MX
# record (as the last refresh stored it, AwsSesSnapshot), received email,
# re-importing and the receiving settings. Redmine's page (HTML, with
# redirects and flash messages), and the same data and actions as JSON for the
# new UI's tab (AwsSesMailReceiving of frontend/;
# AwsSesMailHelper#aws_ses_mail_receiving_json).
class AwsSesMailReceivingController < ApplicationController
  include RedmineKit::Aws::AdminTab

  helper :aws_ses_mail
  helper :aws_ses_mail_json

  def index
    load_page
    respond_to do |format|
      format.html
      format.json { render json: view_context.aws_ses_mail_receiving_json }
    end
  end

  # On an error, the page again with the values given and the error above
  # the form, as Redmine's settings do (SettingsController#edit).
  def update
    @settings = RedmineKit::Aws::Ses.settings.merge(setting_params)
    @setting_errors = setting_errors(@settings)
    return update_failed if @setting_errors.any?

    Setting.plugin_redmine_kit_aws_ses = @settings
    audit('changed the receiving settings')
    done(l(:notice_successful_update))
  end

  def reimport
    mails = selected_mails
    return render_404 if mails.empty?

    mails.each { |mail| AwsSesReimportMailJob.perform_later(mail.message_id) }
    audit("re-imported #{mails.map(&:message_id).join(', ')}")
    done(l(:notice_aws_ses_mail_reimport, count: mails.size))
  end

  private

  # What the tab shows; the settings given, when a save was refused.
  def load_page
    @settings ||= RedmineKit::Aws::Ses.settings
    @domain = RedmineKit::Aws::Ses.domain
    @snapshot = AwsSesSnapshot.latest
    @project_settings = AwsSesProjectMailSetting.includes(:project).order(:id).to_a
    @received = received_mails
  end

  # Back to the tab with the notice, or the notice as JSON.
  def done(notice)
    respond_to do |format|
      format.html do
        flash[:notice] = notice
        redirect_to action: 'index'
      end
      format.json { render json: { notice: notice, errors: [] } }
    end
  end

  # The settings refused: the page again with the values given and the errors,
  # or the errors as JSON (422).
  def update_failed
    respond_to do |format|
      format.html do
        load_page
        render :index
      end
      format.json { render json: { errors: @setting_errors }, status: :unprocessable_content }
    end
  end

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
    values = values.is_a?(ActionController::Parameters) ? values.permit(*RedmineKit::Aws::Ses::DEFAULTS.keys).to_h : {}
    values['global_local_part'] = values['global_local_part'].to_s.strip.downcase if values.key?('global_local_part')
    values
  end

  # The errors of the settings: the address, a value of global_mail, and an
  # active project's identifier (or none) as the default project, the choices
  # the form offers. A full message as Rails composes one (errors.format,
  # "%{attribute} %{message}"), with Redmine's own strings.
  def setting_errors(settings)
    address = settings['global_local_part'].to_s
    project = settings['default_project'].to_s
    [
      (l(:error_aws_ses_mail_local_part) unless address.match?(AwsSesProjectMailSetting::LOCAL_PART)),
      (not_in_list(:label_incoming_emails) unless RedmineKit::Aws::Ses::GLOBAL_MAIL.include?(settings['global_mail'])),
      (not_in_list(:label_aws_ses_mail_default_project) unless project.empty? || active_project?(project))
    ].compact
  end

  def active_project?(identifier)
    Project.active.exists?(identifier: identifier)
  end

  def not_in_list(label)
    "#{l(label)} #{l('activerecord.errors.messages.inclusion')}"
  end

  def audit(what)
    logger&.info "[redmine_kit_aws_ses] #{User.current.login} #{what}"
  end
end
