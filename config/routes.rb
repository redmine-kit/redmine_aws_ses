# frozen_string_literal: true

# The shared entry of the Serverless administration menu (every Redmine
# Serverless plugin draws it; the first one matches).
get 'admin/serverless', to: 'serverless_admin#index'

get 'admin/serverless/mail_sending', to: 'serverless_mail_sending#index', as: 'serverless_mail_sending'
post 'admin/serverless/mail_sending/unsuppress', to: 'serverless_mail_sending#unsuppress',
                                                 as: 'serverless_mail_unsuppress'
get 'admin/serverless/mail_receiving', to: 'serverless_mail_receiving#index', as: 'serverless_mail_receiving'
post 'admin/serverless/mail_receiving', to: 'serverless_mail_receiving#update'
post 'admin/serverless/mail_receiving/reimport', to: 'serverless_mail_receiving#reimport',
                                                 as: 'serverless_mail_reimport'
patch 'projects/:project_id/serverless_mail_setting', to: 'serverless_project_mail_settings#update',
                                                      as: 'serverless_project_mail_setting'
