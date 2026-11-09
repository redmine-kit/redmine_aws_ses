# Redmine Serverless SES

Redmine Serverless SES (`redmine_serverless_ses`) is a Redmine plugin for sending and receiving Redmine's email with Amazon SES: retries of sending by error type, importing email that SES received, checks against spoofing and spam, and addresses per project. It does not modify Redmine's own files and uses only Redmine's standard extension mechanisms. The plugin is in early development (version 0.1.1).

- [Setup](setup.md): requirements, installation, configuration, AWS resources, network, tests
- [IAM permissions](iam.md): permissions, example policy, resource-based policies
- [Sending](sending.md): errors by kind and retries, sending again, senders per project
- [Receiving](receiving.md): addresses, importing, spoofing and spam
- [Administration pages](admin.md): sending email, receiving email, project email settings

## Features

| Feature | Contents | Enabled when | Page |
| --- | --- | --- | --- |
| Retrying mail sending | `raise_delivery_errors` in the process that runs jobs, retries by SES error type (temporary errors are retried, account problems are kept for resending, message problems are dropped) | `REDMINE_ROLE=worker` on Lambda. Outside Lambda, in the process that runs jobs | [sending.md](sending.md) |
| Mail receiving | Importing email that SES stored in S3 (the rake task `redmine_serverless_ses:receive_mail`, which uses Redmine's standard `MailHandler` inside), checks of the SES event's verdicts (spam and DMARC configurable, viruses always dropped), import records | Receiving settings exist | [receiving.md](receiving.md#importing) |
| Addresses per project | Receiving address and sender per project, a global address, an "Email" tab in project settings | Enabled in the plugin settings. When disabled, same as standard Redmine (one sender, projects selected by subaddress `redmine+identifier@…`) | [receiving.md](receiving.md#addresses-per-project) |
| Administration pages | The "Sending email" and "Receiving email" tabs under the shared "Serverless" menu (SES status, received email), and the project email settings in project settings | Administrators. Pages for unused features are not shown | [admin.md](admin.md) |

- **With or without Lambda:** Sending through SES (`aws-actionmailer-ses`) and receiving work in any Redmine that can reach SES and S3; the receiving task is started with the message ID of the received email. On AWS Lambda, [Serverless](https://redmine-kit.github.io/serverless/) installs it together with [Redmine Serverless SQS](https://redmine-kit.github.io/redmine_serverless_sqs/), which runs the jobs that send email, records the ones that fail for the last time and lets them be resent.
- **Gems and code structure:** The gem depends on `aws-actionmailer-ses`, `aws-sdk-sesv2` and `aws-sdk-s3` (with a checkout, the plugin's `Gemfile` adds them). `boot/redmine_serverless_ses.rb` loads `aws-actionmailer-ses` (the delivery method `:ses_v2`) and registers the interceptor for per-project senders; Bundler loads it before Rails initializes, because the plugin is also a gem ([setup.md](setup.md#installation)). The rest is in `lib/redmine_serverless_ses/`, `app/` and `db/`, which Redmine loads, and `init.rb` turns it on.
- **Tests:** Tests are written with Redmine's standard mechanism and run in Docker with moto ([setup.md](setup.md#tests)). Mail import tests use messages with the headers SES adds ([testing.md](https://redmine-kit.github.io/serverless/testing.html#email-redmine_serverless_ses)).
- **Migrations:** Add tables for received mail records (`serverless_received_mails`) and project mail settings (`serverless_project_mail_settings`) ([admin.md](admin.md)).
