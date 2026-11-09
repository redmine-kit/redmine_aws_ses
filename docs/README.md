# Redmine Serverless SES

Redmine Serverless SES (`redmine_serverless_ses`) is a Redmine plugin for sending and receiving Redmine's email with Amazon SES: retries of sending by error type, importing email that SES received, checks against spoofing and spam, and addresses per project. It does not modify Redmine's own files and uses only Redmine's standard extension mechanisms. The plugin is in the design stage, and only the documentation exists.

- [Administration pages](admin.md): sending email, receiving email, project email settings

## Features

| Feature | Contents | Enabled when | Design |
| --- | --- | --- | --- |
| Retrying mail sending | `raise_delivery_errors` in the process that runs jobs, retries by SES error type (temporary errors are retried, account problems are kept for resending, message problems are dropped) | `REDMINE_ROLE=worker` on Lambda. Outside Lambda, in the process that runs jobs | [mail.md](https://redmine-kit.github.io/serverless/mail.html#when-sending-fails) |
| Mail receiving | Importing email that SES stored in S3 (the rake task `redmine_serverless_ses:receive_mail`, which uses Redmine's standard `MailHandler` inside), spoofing and spam checks, import records | Receiving settings exist | [mail.md](https://redmine-kit.github.io/serverless/mail.html#importing) |
| Addresses per project | Receiving address and sender per project, a global address, an "Email" tab in project settings | Enabled in the plugin settings. When disabled, same as standard Redmine (one sender, projects selected by subaddress `redmine+identifier@…`) | [mail.md](https://redmine-kit.github.io/serverless/mail.html#addresses-per-project) |
| Administration pages | Sending email (SES status), receiving email, project email settings | Administrators. Pages for unused features are not shown | [admin.md](admin.md) |

- **With or without Lambda:** Sending through SES (`aws-actionmailer-ses`) and receiving work in any Redmine that can reach SES and S3; the receiving task is started with the message ID of the received email. On AWS Lambda, [Serverless](https://redmine-kit.github.io/serverless/) installs it together with [Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/), which records jobs that fail for the last time and lets them be resent.
- **Gems:** Gems the plugin uses go in the plugin's `Gemfile`. Redmine's `Gemfile` also loads `plugins/*/Gemfile`.
- **Tests:** Tests are written with Redmine's standard mechanism (`rake redmine:plugins:test`). Mail import tests use Redmine's test mail samples with the headers SES adds ([testing.md](https://redmine-kit.github.io/serverless/testing.html#running-on-lambda-and-email)).
- **Migrations:** Add tables for received mail records (`serverless_received_mails`) and project mail settings (`serverless_project_mail_settings`) ([admin.md](admin.md)).
