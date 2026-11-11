# Setup

What a Redmine needs to use Redmine AWS SES: installation, configuration, the SES and S3 resources, IAM permissions and network access. It works on AWS Lambda and on an ordinary server alike. [Serverless](https://redmine-kit.github.io/serverless/) sets all of this up with CloudFormation; this page is for setting it up by hand, or for checking what Serverless creates.

## Requirements

- Redmine 7.0 or later.
- [Redmine AWS](https://redmine-kit.github.io/redmine_aws/) (`redmine_aws`) 0.1 or later, in `plugins/redmine_aws`. Redmine refuses to start without it (`requires_redmine_plugin` in `init.rb`), and the gem depends on it. It adds the "AWS" administration menu.
- A process that can reach SES and S3 with AWS credentials (an execution role on Lambda, an instance profile or a task role elsewhere). No access keys or SMTP passwords are stored in Redmine.
- For sending: the official AWS gem `aws-actionmailer-ses` (delivery method `:ses_v2`) ([Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#gems)).
- For retries of sending: jobs that run in a process of their own (on Lambda, `REDMINE_ROLE=worker`; [Redmine AWS SQS](https://redmine-kit.github.io/redmine_aws_sqs/) records the jobs that fail for the last time).

## Installation

1. Get the plugin into `plugins/redmine_aws_ses` of Redmine 7.0, and Redmine AWS into `plugins/redmine_aws`: the gems below, or checkouts of the repositories.
2. Add the plugin to `Gemfile.local` as a gem, and install it:

   ```sh
   bundle install
   ```

   Bundler then loads `boot/redmine_aws_ses.rb` before Rails initializes: it loads `aws-actionmailer-ses`, which registers the delivery method `:ses_v2`, and the interceptor for per-project senders. With checkouts, add both by path. Redmine AWS must be listed too, because the plugin's gemspec requires it and it is not on rubygems.org; Bundler does not load it (Redmine does). List it once, even when you add several Redmine AWS plugins this way: Bundler refuses the same gem from two sources and warns about duplicates.

   ```ruby
   # Redmine's Gemfile.local
   gem 'redmine_aws', path: 'plugins/redmine_aws', require: false
   gem 'redmine_aws_ses', path: 'plugins/redmine_aws_ses'
   ```

3. Run the plugin's migrations:

   ```sh
   bin/rake redmine:plugins:migrate
   ```

   They create the tables of received mail records (`aws_ses_received_mails`) and project mail settings (`aws_ses_project_mail_settings`).
4. Set sending in `config/configuration.yml`:

   ```yaml
   production:
     email_delivery:
       delivery_method: :ses_v2
       ses_v2_settings:
         region: <region>
   ```

### Gem

Each version tag (`v*`) publishes the plugin as a gem to GitHub Packages (`https://rubygems.pkg.github.com/redmine-kit`; `.github/workflows/gem.yml`). The gem holds the run-time files (`init.rb`, `boot/`, `lib/`, `app/`, `config/`, `db/`, `help/`, `LICENSE`) and depends on `redmine_aws`, `aws-actionmailer-ses`, `aws-sdk-sesv2` and `aws-sdk-s3`; the plugin's `Gemfile` is not in it. Bundler installs the gem of Redmine AWS with it, from the same source, so `Gemfile.local` names only the plugin. Redmine loads plugins only from `plugins/`, so the installed gems are linked there:

```ruby
# Redmine's Gemfile.local
source 'https://rubygems.pkg.github.com/redmine-kit' do
  gem 'redmine_aws_ses'
end
```

```sh
bundle config set --global rubygems.pkg.github.com <user>:<token>   # or BUNDLE_RUBYGEMS__PKG__GITHUB__COM
bundle install
ln -s "$(bundle info --path redmine_aws)" plugins/redmine_aws
ln -s "$(bundle info --path redmine_aws_ses)" plugins/redmine_aws_ses
```

Installing from GitHub Packages needs a GitHub token with `read:packages`, even for a public package. A workflow of another repository reads it with its `GITHUB_TOKEN` (`packages: read`) once the package's settings ("Manage Actions access") give that repository Read.

## Configuration

| Key | Description | Parameter |
| --- | --- | --- |
| `REDMINE_MAIL_BUCKET` | The bucket where SES stores received email (`inbound/<message ID>`; imported email moves to `processed/`) | Required for receiving. Set it in the processes that import (the task, and the worker for re-imports) |
| `REDMINE_ROLE` | Turns on retries of sending only in the process that runs jobs (below) | `worker` in the process that runs jobs |

| Item | Description | Where to change |
| --- | --- | --- |
| Emission email address (`Setting.mail_from`) | The default address, on the verified domain (for example `noreply@redmine.example.com`) ([receiving.md](receiving.md#address-for-the-whole-redmine)) | Redmine's administration settings |
| Receiving settings | The part before `@` of the default address, what to do with email sent to it, the default project, and whether to fetch spam and email that fails DMARC ([admin.md](admin.md#receiving-email)) | Plugin settings. In Serverless, `pluginSettings` in `redmine.json` |
| Addresses per project | On or off. Default off, the same as standard Redmine. Per-project settings are in the "Email" tab of each project ([admin.md](admin.md#project-email-settings)) | Plugin settings |
| Truncate emails after one of these lines | A line before the quoted text, so that replies do not bring the quote into notes | Redmine's administration settings |

### Receiving defaults

By default, the part before `@` of the default address is `noreply`, and email to it is not fetched ("Do not fetch"). To fetch it, choose the part before `@` (for example `redmine`) when switching to "Fetch into the default project". An installation that has already saved the receiving settings keeps its value. Fetching spam (`import_spam`) and email that fails DMARC (`import_without_dmarc_pass`) are both off by default.

### Sending errors

The plugin sets `raise_delivery_errors` to `true` only in the process that runs jobs (`REDMINE_ROLE=worker`; outside Lambda, set it in the poller's process), so that SES errors reach Redmine's mail job (`Mailer::DeliveryJob`). Other processes keep Redmine's `false`, so that one failed message does not stop a rake task ([sending.md](sending.md)).

In the job, the kind of error decides what happens: temporary errors are retried inside the job, message errors drop the job, and account errors go to the queue's retries and dead-letter queue ([sending.md](sending.md#handling-by-kind-of-error)).

### Importing received mail

The rake task `redmine_aws_ses:receive_mail` imports one received message, so something must start it for each message. On Lambda, the SES receipt rule invokes the task function asynchronously, and its handler passes the values of the SES event as variables ([Serverless tasks.md](https://redmine-kit.github.io/serverless/tasks.html#kinds-of-events)):

| Variable | From the SES event |
| --- | --- |
| `MESSAGE_ID` | `mail.messageId` |
| `SES_RECIPIENTS` | `receipt.recipients`, comma-separated |
| `SES_MAIL_FROM` | `mail.source`, the envelope sender (for registered forwarders; optional) ([receiving.md](receiving.md#forwarded-email)) |
| `SES_SPAM_VERDICT`<br>`SES_VIRUS_VERDICT`<br>`SES_DMARC_VERDICT`<br>`SES_SPF_VERDICT`<br>`SES_DKIM_VERDICT`<br>`SES_DMARC_POLICY` | The verdicts |

A message is imported only if its virus verdict is `PASS`, and its spam and DMARC verdicts are `PASS` unless the receiving settings import them. The verdicts and recipients come from the event, never from the message's headers ([receiving.md](receiving.md#spoofing-and-spam)).

<a id="refreshing-the-ses-state"></a>

### Refreshing the SES state

The "Email sending" and "Email receiving" tabs show the state of SES (the account, the domain's identity, the suppression list) and the domain's MX record as this task last read it, and never call SES or DNS while a page opens ([admin.md](admin.md)). Run it on a schedule, for example once an hour; the tabs' "Refresh" link runs the same reading. It fails when a section could not be read (the log has the error).

```sh
bin/rake redmine_aws_ses:refresh
```

### Keeping records

This task deletes the import records older than the given number of days (default 90). Serverless runs it daily ([Serverless security.md](https://redmine-kit.github.io/serverless/security.html#retention-periods)).

```sh
bin/rake redmine_aws_ses:prune_records[<days>]
```

## AWS resources

| Resource | Settings |
| --- | --- |
| SES domain identity | Redmine's subdomain (for example `redmine.example.com`), verified with Easy DKIM, in the Region used. Used for both sending and receiving |
| SES production access | Requested in advance (leaving the sandbox), per Region |
| DNS | MX of the subdomain to the SES receiving endpoint (`inbound-smtp.<region>.amazonaws.com`, priority 10), and the Easy DKIM CNAMEs ([Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#receiving-domain)) |
| Receipt rule | In the Region's active rule set. Recipient: the subdomain. TLS required. Spam and virus scanning on. First action: store in the mail bucket under `inbound/`. Second action: start the import (on Lambda, invoke the task function asynchronously) ([Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#receipt-rules)) |
| Mail bucket | `inbound/` (received) and `processed/` (imported). Both are deleted after 30 days by lifecycle. A bucket policy lets only SES write to `inbound/`, and denies requests without TLS |

## IAM permissions

The permissions the plugin needs, with an example policy, are in [iam.md](iam.md).

## Network

| From | To | In a VPC without internet access |
| --- | --- | --- |
| Redmine | The SES v2 API (`SendEmail`, the administration page) | An interface endpoint for the SES API, or a NAT instance. The endpoint's service name is checked when building (not checked yet) |
| Redmine | S3 (the mail bucket) | The S3 gateway endpoint (`com.amazonaws.<region>.s3`) |
| Senders | SES receiving (SMTP) | Outside the VPC; SES receives the email |

## Tests

The tests are in `test/` and run with Redmine's standard mechanism, in Redmine 7.0.3 on PostgreSQL 16 in Docker. AWS is LocalStack when `LOCALSTACK_AUTH_TOKEN` is set (CI uses the organization's secret): SES v2 and S3 both run on it, and if LocalStack does not start, the run fails. Without the token (pull requests from forks, local runs), the same tests run on moto. The log names the backend.

Calls that LocalStack does not emulate as real AWS behaves are mocked with SDK response stubs (`stub_responses`), only for that call:

| Call | Why it is mocked | The mocked answer |
| --- | --- | --- |
| SES v2 `GetAccount` (the connection test, the "Email sending" tab) | LocalStack answers that it does not support it; moto does not have it (checked on 2026-11-09) | The fields of the API reference (`ProductionAccessEnabled`, `SendingEnabled`, `SendQuota`, ...), and its errors |
| SES v2 `SendEmail` from a sender that is not a verified identity | Real SES rejects it with `MessageRejected`; LocalStack sends it | `MessageRejected` with SES's message ("Email address is not verified. ...") |
| Each `SendEmail` error by kind ([sending.md](sending.md#handling-by-kind-of-error)) | The emulators cannot be made to answer throttling or account errors | Each error code of the API reference |

What each test checks is in [sending.md](sending.md#tests) and [receiving.md](receiving.md#tests). SES errors are raised one by one through the delivery method with SDK response stubs; the pages use stubs too. The import tests store messages in moto's S3 and import them with the event's verdicts and recipients: the project of the recipient, Bcc, a `Project:` keyword that cannot change the project, each reason for dropping, forged SES headers that change nothing, and re-imports from the record. A test also checks, in new processes, that Redmine's code loader (Zeitwerk) loads the plugin's files under the namespace of Redmine AWS, with the boot file loaded first (`bin/rails zeitwerk:check`). `bin/test` runs the plugin's tests, then Redmine's tests around email (`MailHandler`, `Mailer`, projects, settings, administration); `bin/test --redmine` runs every Redmine test with the plugin installed, as the CI does.

CI runs the lint and the tests on Ruby 3.2 and 4.0; locally, `TEST_RUBY=3.2 bin/test` (or `bin/lint`) runs them on Ruby 3.2.

The tests need Redmine AWS: a checkout of [redmine_aws](https://github.com/redmine-kit/redmine_aws) next to this repository (`../redmine_aws`), or its path in `REDMINE_AWS_DIR`. CI checks it out.

The plugin's tests also write the coverage of the plugin's own files (SimpleCov, Cobertura XML in `coverage/coverage.xml`), which CI uploads to [Codecov](https://codecov.io/gh/redmine-kit/redmine_aws_ses).

```sh
bin/test            # the plugin's tests and Redmine's tests around email
bin/test --redmine  # with every Redmine test
REDMINE_AWS_DIR=<dir> bin/test  # with redmine_aws from <dir>
bin/lint            # RuboCop
bin/services --down # stops PostgreSQL, moto and LocalStack
```

## To verify

- Whether SES v2 `SendEmail` with the full message needs `ses:SendRawEmail`
- The service name of the interface endpoint for the SES API
- Which identity SES's SPF verdict checks (RFC 7208 checks the MAIL FROM identity, and the HELO identity when MAIL FROM is empty); SES's documentation does not say. Registered forwarders rely on it being MAIL FROM
- Which envelope sender Google Workspace's recipient address maps and Gmail's forwarding give a forwarded message (Google's documentation does not say), and so whether a registered forwarder matches
- The exact lines of forwarded blocks in the Japanese interfaces of Gmail (「転送されたメッセージ」) and Outlook (「差出人:」「送信日時:」「宛先:」「件名:」): not documented, and not checked against forwards from those products yet
- The open questions of the mail design in [Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#to-verify)
