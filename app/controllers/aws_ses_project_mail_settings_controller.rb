# frozen_string_literal: true

# The "Email" tab of project settings (docs/admin.md#project-email-settings).
class AwsSesProjectMailSettingsController < ApplicationController
  menu_item :settings

  before_action :find_project_by_project_id, :authorize

  def update
    setting = AwsSesProjectMailSetting.find_or_initialize_by(project: @project)
    setting.safe_attributes = params.require(:aws_ses_project_mail_setting).permit!.to_h
    if setting.save
      logger&.info "[redmine_aws_ses] #{User.current.login} changed the email settings of #{@project.identifier}"
      flash[:notice] = l(:notice_successful_update)
    else
      flash[:error] = setting.errors.full_messages.join(', ')
    end
    redirect_to settings_project_path(@project, tab: 'aws_ses_mail')
  end
end
