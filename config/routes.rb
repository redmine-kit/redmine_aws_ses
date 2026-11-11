# frozen_string_literal: true

# The email tabs of the AWS administration page (redmine_aws draws admin/aws
# itself) and the Email tab of project settings.
get 'admin/aws/mail_sending', to: 'aws_ses_mail_sending#index', as: 'aws_ses_mail_sending'
post 'admin/aws/mail_sending/unsuppress', to: 'aws_ses_mail_sending#unsuppress', as: 'aws_ses_mail_unsuppress'
get 'admin/aws/mail_receiving', to: 'aws_ses_mail_receiving#index', as: 'aws_ses_mail_receiving'
post 'admin/aws/mail_receiving', to: 'aws_ses_mail_receiving#update'
post 'admin/aws/mail_receiving/reimport', to: 'aws_ses_mail_receiving#reimport', as: 'aws_ses_mail_reimport'
patch 'projects/:project_id/aws_ses_mail_setting', to: 'aws_ses_project_mail_settings#update',
                                                   as: 'aws_ses_project_mail_setting'
