# Redmine AWS SES

Redmine AWS SES (`redmine_aws_ses`) is a Redmine plugin for sending and receiving Redmine's email with Amazon SES: retries of sending by error type, importing email that SES received, checks against spoofing and spam, and addresses per project. It requires [Redmine AWS](https://redmine-kit.github.io/redmine_aws/) (`redmine_aws`). It does not modify Redmine's own files and uses only Redmine's standard extension mechanisms. The plugin is in early development.

- [Setup](setup.md): requirements, installation, configuration, AWS resources, network, tests
- [IAM permissions](iam.md): permissions, example policy, resource-based policies
- [Sending](sending.md): errors by kind and retries, sending again, senders per project
- [Receiving](receiving.md): addresses, importing, spoofing and spam
- [Administration pages](admin.md): email sending, email receiving, project email settings

## Features

| Feature | Contents | Enabled when | Page |
| --- | --- | --- | --- |
| Retrying mail sending | `raise_delivery_errors` in the process that runs jobs, retries by SES error type (temporary errors are retried, account problems are kept for resending, message problems are dropped) | `REDMINE_ROLE=worker` on Lambda. Outside Lambda, in the process that runs jobs | [sending.md](sending.md) |
| Mail receiving | Importing email that SES stored in S3 (the rake task `redmine_aws_ses:receive_mail`, which uses Redmine's standard `MailHandler` inside), checks of the SES event's verdicts (spam and DMARC configurable, viruses always dropped), import records | Receiving settings exist | [receiving.md](receiving.md#importing) |
| Addresses per project | Receiving address and sender per project, a default address, an "Email" tab in project settings | Enabled in the plugin settings. When disabled, same as standard Redmine (one sender, projects selected by subaddress `noreply+identifier@…`) | [receiving.md](receiving.md#addresses-per-project) |
| Administration pages | The "Email sending" and "Email receiving" tabs under the "AWS" menu of [Redmine AWS](https://redmine-kit.github.io/redmine_aws/admin.html#the-aws-menu) (SES account, received emails), and the project email settings in project settings | Administrators. Pages for unused features are not shown | [admin.md](admin.md) |

## Outside Lambda

Sending through SES (`aws-actionmailer-ses`) and receiving work in any Redmine that can reach SES and S3. The receiving task is started with the message ID of the received email.

On AWS Lambda, [Serverless](https://redmine-kit.github.io/serverless/) installs the plugin together with [Redmine AWS SQS](https://redmine-kit.github.io/redmine_aws_sqs/). That plugin runs the jobs that send email, records the ones that fail for the last time and lets them be resent.

## Gems and code layout

The gem depends on `redmine_aws`, `aws-actionmailer-ses`, `aws-sdk-sesv2` and `aws-sdk-s3`; with a checkout, the plugin's `Gemfile` adds the AWS gems, and Redmine AWS is a checkout of its own in `plugins/redmine_aws`.

`boot/redmine_aws_ses.rb` loads `aws-actionmailer-ses` (the delivery method `:ses_v2`) and registers the interceptor for per-project senders. Because the plugin is also a gem, Bundler loads this file before Rails initializes ([setup.md](setup.md#installation)). The rest is in `lib/redmine_aws/ses.rb` and `lib/redmine_aws/ses/` (the module `RedmineAws::SES`, inside the namespace of Redmine AWS), `app/` and `db/`, which Redmine loads, and `init.rb` turns it on. The "AWS" administration menu, its tabs and the connection test come from [Redmine AWS](https://redmine-kit.github.io/redmine_aws/), which the plugin requires.

## Tests

The tests use Redmine's standard mechanism and run in Docker ([setup.md](setup.md#tests)). The mail import tests use messages with the headers SES adds ([testing.md](https://redmine-kit.github.io/serverless/testing.html#email-redmine_aws_ses)).

## Database tables

The plugin adds three tables: the records of received mail (`aws_ses_received_mails`), the projects' mail settings (`aws_ses_project_mail_settings`) and the state of SES that the email tabs show (`aws_ses_snapshots`) ([admin.md](admin.md)).

## Sponsors

<Sponsors><a href="https://www.keyselect.co.jp/">KEY SELECT</a> <a href="https://localstack.cloud">LocalStack</a></Sponsors>

## License

Redmine AWS SES is released under the GNU General Public License, version 2 or (at your option) any later version. See [LICENSE](../LICENSE). An unofficial Redmine plugin.
