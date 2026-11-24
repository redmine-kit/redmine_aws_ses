# frozen_string_literal: true

# The "Email" tab of project settings (docs/admin.md#project-email-settings):
# Redmine's tab (a partial of project settings) and its save, and the same
# values and save as JSON for the new UI's tab (AwsSesProjectMail of frontend/;
# AwsSesMailHelper#aws_ses_project_mail_json). Only while addresses per
# project are on, as the tab is listed (ProjectSettingsTab).
class AwsSesProjectMailSettingsController < ApplicationController
  menu_item :settings

  helper :aws_ses_mail
  helper :aws_ses_mail_json

  before_action :find_project_by_project_id, :authorize
  before_action :find_setting

  # GET projects/:project_id/aws_ses_mail_setting.json
  def show
    render json: view_context.aws_ses_project_mail_json(@setting)
  end

  def update
    @setting.safe_attributes = setting_params(@setting)
    @setting.save ? saved : save_failed
  end

  private

  # Back to Redmine's tab with the notice, or the saved values as JSON.
  def saved
    logger&.info "[redmine_kit_aws_ses] #{User.current.login} changed the email settings of #{@project.identifier}"
    respond_to do |format|
      format.html do
        flash[:notice] = l(:notice_successful_update)
        redirect_to settings_project_path(@project, tab: 'aws_ses_mail')
      end
      format.json { render json: view_context.aws_ses_project_mail_json(@setting) }
    end
  end

  # The form again with the errors, or the errors as JSON (422).
  def save_failed
    respond_to do |format|
      format.html { render :edit }
      format.json { render json: { errors: @setting.errors.full_messages }, status: :unprocessable_content }
    end
  end

  # The project's setting; the tab is there only while addresses per project
  # are on (RedmineKit::Aws::Ses::ProjectSettingsTab), and its JSON too.
  def find_setting
    return render_404 if request.format.json? && !RedmineKit::Aws::Ses::ProjectSettingsTab.enabled?(@project)

    @setting = AwsSesProjectMailSetting.find_or_initialize_by(project: @project)
  end

  # The safe attributes, each a single value; a parameter of another shape is
  # ignored.
  def setting_params(setting)
    values = params[:aws_ses_project_mail_setting]
    values.is_a?(ActionController::Parameters) ? values.permit(*setting.safe_attribute_names) : {}
  end
end
