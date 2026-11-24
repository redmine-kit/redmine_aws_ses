# Setup

What a Redmine needs to use Redmine Kit AWS SES: installation, configuration, the SES and S3 resources, IAM permissions and network access. It works on AWS Lambda and on an ordinary server alike. [Serverless](https://redmine-kit.github.io/serverless/) sets all of this up with CloudFormation; this page is for setting it up by hand, or for checking what Serverless creates.

## Requirements

- Redmine 7.0 or later.
- A process that can reach SES and S3 with AWS credentials (an execution role on Lambda, an instance profile or a task role elsewhere). No access keys or SMTP passwords are stored in Redmine.
- For sending: the official AWS gem `aws-actionmailer-ses` (delivery method `:ses_v2`) ([Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#gems)).

### Required plugins

| Plugin | Used for |
| --- | --- |
| [Redmine Kit AWS](https://github.com/redmine-kit/redmine_aws) | the AWS administration menu and the settings shared by the AWS plugins |

Without it, Redmine stops at boot and names it. Installed as a gem, this plugin installs it
([Installation](#installation)).

### Optional plugins

| Plugin | With it |
| --- | --- |
| [Redmine Kit AWS SQS](https://github.com/redmine-kit/redmine_aws_sqs) | the re-import of received mail as a job on SQS |
| [Redmine Kit Help](https://github.com/redmine-kit/redmine_help) | this plugin's help in the Help panel |
| [Redmine Kit UI](https://github.com/redmine-kit/redmine_kit_ui) | the new UI's screens of the email tabs and of a project's Email tab ([admin.md](admin.md#in-the-new-ui)) |

## Installation

1. Install the plugin as a gem ([Gem](#gem)), or put checkouts of it and of [Redmine Kit AWS](https://redmine-kit.github.io/redmine_aws/), which it requires, in Redmine's `plugins/` ([Without the gem](#without-the-gem)). The order doesn't matter: at boot, Redmine stops and names `redmine_kit_aws` when it is missing ([Required plugins](#required-plugins)).
2. Run `bundle install` in Redmine's folder.
3. Run the plugin's migrations:

   ```sh
   bin/rails redmine:plugins:migrate RAILS_ENV=production
   ```

   They create the tables of received mail records (`aws_ses_received_mails`), project mail settings (`aws_ses_project_mail_settings`) and the SES state (`aws_ses_snapshots`).
4. Set sending in `config/configuration.yml`:

   ```yaml
   production:
     email_delivery:
       delivery_method: :ses_v2
       ses_v2_settings:
         region: <region>
   ```
5. Restart Redmine.

### Gem

**As a gem** (first choice): add it to Redmine's `Gemfile.local`, in a block of Redmine Kit's registry on GitHub Packages (`https://rubygems.pkg.github.com/redmine-kit`, where `bin/release` publishes it: [Releasing](#releasing)). Bundler takes the plugins it requires from there too ([Required plugins](#required-plugins)), and never takes these gems from rubygems.org. The registry needs a GitHub token with `read:packages`, even for a public package, given to Bundler in the environment variable `BUNDLE_RUBYGEMS__PKG__GITHUB__COM` (`<user>:<token>`), never in a file of a repository.

```ruby
# Redmine's Gemfile.local
source 'https://rubygems.pkg.github.com/redmine-kit' do
  gem 'redmine_kit_aws_ses'
end
```

**From the repositories** (for development), Bundler takes the gems from git instead; it doesn't take the plugins a gem requires from git, so their lines come too:

```ruby
# Redmine's Gemfile.local
gem 'redmine_kit_aws', git: 'https://github.com/redmine-kit/redmine_aws.git', branch: 'main'
gem 'redmine_kit_aws_ses', git: 'https://github.com/redmine-kit/redmine_aws_ses.git', branch: 'main'
```

Bundler requires `boot/redmine_kit_aws_ses.rb`, which hands the gem's folder to Redmine's plugin loader (and, from the gems it depends on, Redmine Kit AWS's): Redmine runs the gem's `init.rb`, serves its assets, strings, views and migrations, adds its `lib/` and `app/` to Rails' code loader and draws its routes, as for a plugin in `plugins/`, so no link in `plugins/` is needed. A folder of the same id in `plugins/` wins over the gem. The file also does what must be in place before Rails initializes: it loads `aws-actionmailer-ses`, which registers the delivery method `:ses_v2`, and the interceptor for per-project senders. The gem holds the run-time files; the plugin's `Gemfile` is not in it.

### Without the gem

Clone the repositories into Redmine's `plugins/`, in folders named after the plugins' ids, which differ from the repositories' names:

```sh
git clone https://github.com/redmine-kit/redmine_aws.git plugins/redmine_kit_aws
git clone https://github.com/redmine-kit/redmine_aws_ses.git plugins/redmine_kit_aws_ses
```

The plugin's `Gemfile`, which Redmine's `Gemfile` loads, names the plugin by its path, so that Bundler loads `boot/redmine_kit_aws_ses.rb` before Rails initializes as the gem's does, and Redmine Kit AWS by the path of its checkout next to it (each unless `Gemfile.local` or another plugin's `Gemfile` names it already). No line in `Gemfile.local` is needed.

## Configuration

| Key | Description | Parameter |
| --- | --- | --- |
| `REDMINE_SES_MAIL_BUCKET` | The bucket where SES stores received email (`inbound/<message ID>`; imported email moves to `processed/`) | Required for receiving. Set it in the processes that import (the task, and the worker for re-imports) |
| `REDMINE_ROLE` | Turns on retries of sending only in the process that runs jobs (below) | `worker` in the process that runs jobs |

| Item | Description | Where to change |
| --- | --- | --- |
| Emission email address (`Setting.mail_from`) | The default address, on the verified domain (for example `noreply@redmine.example.com`) ([receiving.md](receiving.md#address-for-the-whole-redmine)) | Redmine's administration settings |
| Receiving settings | The part before `@` of the default address, what to do with email sent to it, the default project, and whether to fetch spam and email that fails DMARC ([admin.md](admin.md#receiving-email)) | Plugin settings. In Serverless, `pluginSettings` in `redmine.json` |
| Addresses per project | On or off. Default off, the same as standard Redmine. Per-project settings are in the "Email" tab of each project ([admin.md](admin.md#project-email-settings)) | Plugin settings |
| Senders per project | On or off. Default off. With addresses per project, project notifications are sent from the project's address ([sending.md](sending.md#senders-per-project)) | Plugin settings |
| Truncate emails after one of these lines | A line before the quoted text, so that replies do not bring the quote into notes | Redmine's administration settings |

### Receiving defaults

By default, the part before `@` of the default address is `noreply`, and email to it is not fetched ("Do not fetch"). To fetch it, choose the part before `@` (for example `redmine`) when switching to "Fetch into the default project". An installation that has already saved the receiving settings keeps its value. Fetching spam (`import_spam`) and email that fails DMARC (`import_without_dmarc_pass`) are both off by default.

### Sending errors

The plugin sets `raise_delivery_errors` to `true` only in the process that runs jobs (`REDMINE_ROLE=worker`; outside Lambda, set it in the poller's process), so that SES errors reach Redmine's mail job (`Mailer::DeliveryJob`). Other processes keep Redmine's `false`, so that one failed message does not stop a rake task ([sending.md](sending.md)).

In the job, the kind of error decides what happens: temporary errors are retried inside the job, message errors drop the job, and account errors go to the queue's retries and dead-letter queue ([sending.md](sending.md#handling-by-kind-of-error)).

### Importing received mail

The rake task `redmine_kit:aws:ses:receive_mail` imports one received message, so something must start it for each message. On Lambda, the SES receipt rule invokes the task function asynchronously, and its handler passes the values of the SES event as variables ([Serverless tasks.md](https://redmine-kit.github.io/serverless/tasks.html#kinds-of-events)):

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
bin/rake redmine_kit:aws:ses:refresh
```

### Keeping records

This task deletes the import records older than a number of days, set with `DAYS` (default 90; a whole number from 1 to 99999), as Redmine's `redmine:users:prune` takes it. Serverless runs it daily ([Serverless security.md](https://redmine-kit.github.io/serverless/security.html#retention-periods)).

```sh
bin/rake redmine_kit:aws:ses:prune DAYS=90
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

The tests are in `test/` and run with Redmine's standard mechanism, in Redmine 7.0.3 on PostgreSQL 16, in Apple container when it is installed and running, else in Docker (`CONTAINER_CLI=container` or `docker` chooses; at most two test runs of the redmine-kit repositories at once on a machine, `TEST_SLOTS`). S3 (the import tests) is [AWS Emulator](https://docs.aws.amazon.com/emulator/latest/userguide/) at a pinned version, with telemetry off (`test/aws-emulator/Dockerfile`). The sending test runs on LocalStack when `LOCALSTACK_AUTH_TOKEN` is set (CI uses the organization's secret) and on moto otherwise, as the emulator cannot run it yet ([sending.md](sending.md#tests)); the log names the backends. The plugin's tests run on an internal network that cannot reach AWS, and a test fails if a connection to AWS opens; Redmine's own tests, which call no AWS API, run on the default network. AWS Emulator's certificate names only `127.0.0.1` and `localhost`, so the tests reach it there: in Docker they run in its network namespace; Apple container can't share one, so they forward `127.0.0.1:9297` to the emulator's container (`bin/aws_emulator`, `test/aws_forward.rb`) and trust the certificate copied out of it.

A run stops the service containers it started (it doesn't remove them) when it ends, whether the tests pass, fail or are interrupted. Containers that were running before the run, or that another run of this repository still uses, are left running. `KEEP_SERVICES=1` keeps them running after the run.

Calls whose answers the tests need but no backend gives as real AWS does are mocked with SDK response stubs (`stub_responses`), only for that call:

| Call | Why it is mocked | The mocked answer |
| --- | --- | --- |
| SES v2 `GetAccount` (the connection test, the "Email sending" tab) | The tests need account states and errors (a paused account, `AccessDeniedException`); AWS Emulator always answers the same sandbox account, LocalStack answers that it does not support it and moto does not have it (checked on 2026-11-09 and 2026-11-12) | The fields of the API reference (`ProductionAccessEnabled`, `SendingEnabled`, `SendQuota`, ...), and its errors |
| SES v2 `SendEmail` from a sender that is not a verified identity | Real SES rejects it with `MessageRejected`; LocalStack sends it | `MessageRejected` with SES's message ("Email address is not verified. ...") |
| Each `SendEmail` error by kind ([sending.md](sending.md#handling-by-kind-of-error)) | The emulators cannot be made to answer throttling or account errors | Each error code of the API reference |

What each test checks is in [sending.md](sending.md#tests) and [receiving.md](receiving.md#tests). SES errors are raised one by one through the delivery method with SDK response stubs; the pages use stubs too. The import tests store messages in the test S3 (AWS Emulator) and import them with the event's verdicts and recipients: the project of the recipient, Bcc, a `Project:` keyword that cannot change the project, each reason for dropping, forged SES headers that change nothing, and re-imports from the record. A test also checks, in new processes, that Redmine's code loader (Zeitwerk) loads the plugin's files under the namespace of Redmine Kit AWS, with the boot file loaded first (`bin/rails zeitwerk:check`). `bin/test` runs the plugin's tests with [Redmine Kit UI](https://github.com/redmine-kit/redmine_kit_ui) installed (from the checkout next to this one, `../redmine_kit_ui` at `HEAD`; `REDMINE_KIT_UI` and `REDMINE_KIT_UI_REF` choose another), then without it, then Redmine's tests around email (`MailHandler`, `Mailer`, projects, settings, administration); `bin/test --redmine` runs every Redmine test with the plugin installed, as the CI does.

CI runs the lint and the tests on Ruby 3.2 and 4.0; locally, `TEST_RUBY=3.2 bin/test` (or `bin/lint`) runs them on Ruby 3.2.

`bin/test-gem` checks the gem as the template of the organization's plugins does: it builds the gems of the plugin and of Redmine Kit AWS from the checkouts, takes the checkouts out of `plugins/`, installs the gems as [Gem](#gem) says and starts Redmine with every file loaded (`zeitwerk:check`, and the production environment, which loads them at start-up), checking that each plugin comes from its gem's folder with its boot file, code, routes, migrations and assets; then again with the checkouts back in `plugins/`, which win. CI runs it too, so a file missing from the gem fails before Serverless installs it.

The tests need Redmine Kit AWS: a checkout of [redmine_kit_aws](https://github.com/redmine-kit/redmine_aws) next to this repository (`../redmine_kit_aws`), or its path in `REDMINE_KIT_AWS_DIR`. CI checks it out.

With `COVERAGE=1`, the plugin's tests also write the coverage of the plugin's own files (SimpleCov, Cobertura XML in `coverage/coverage.xml`) and run in one process. CI sets it on Ruby 4.0 and uploads the report to [Codecov](https://codecov.io/gh/redmine-kit/redmine_aws_ses) with the flag `plugin`. The upload authenticates with OIDC (`id-token: write`), so no token is stored as a secret. Codecov's statuses are informational and never fail a commit or a pull request (`codecov.yml`).

```sh
bin/test            # the plugin's tests and Redmine's tests around email
bin/test --redmine  # with every Redmine test
COVERAGE=1 bin/test # with the coverage in coverage/coverage.xml
REDMINE_KIT_AWS_DIR=<dir> bin/test  # with redmine_kit_aws from <dir>
bin/test-gem        # the gems: built, installed, booted from the gems, then from plugins/
bin/lint            # RuboCop
bin/services --down # stops PostgreSQL, moto and LocalStack
```

The new UI's module is checked in `frontend/` with Node.js (the version in `frontend/.nvmrc`); `.npmrc` has `ignore-scripts=true`, and `@redmine-kit/ui` and `@redmine-kit/plugin` come from the checkout of the ui repository next to this one (`../../ui/packages/…`):

```sh
cd frontend
npm install
npm run check       # type check, the components' tests (vitest), the build, kit-check-ui, the Storybook's build
npm run storybook   # the Storybook of the tab's states, on port 6008
```

## Releasing

`bin/release` publishes the gem of the gemspec's version to Redmine Kit's registry on GitHub Packages, from a clean
`main` only: the version must be newer than the last tag `v<version>`, the required plugins must resolve from the
registry at their ranges (`config/dependencies.yml`), and `bin/lint`, `bin/test` and `bin/test-gem` must pass. It
pushes with the key `github` of `~/.gem/credentials` (`:github: Bearer <token>`, a token with `write:packages`) and
reads the registry with `BUNDLE_RUBYGEMS__PKG__GITHUB__COM`; no token goes into the repository or the output. It makes
the signed tag `v<version>` and prints the command that pushes it. Versions are semantic: a change that breaks a plugin
using this one raises the major version (the minor one before 1.0), and the ranges in the plugins that require it.

## To verify

- Whether SES v2 `SendEmail` with the full message needs `ses:SendRawEmail`
- The service name of the interface endpoint for the SES API
- Which identity SES's SPF verdict checks (RFC 7208 checks the MAIL FROM identity, and the HELO identity when MAIL FROM is empty); SES's documentation does not say. Registered forwarders rely on it being MAIL FROM
- Which envelope sender Google Workspace's recipient address maps and Gmail's forwarding give a forwarded message (Google's documentation does not say), and so whether a registered forwarder matches
- The exact lines of forwarded blocks in the Japanese interfaces of Gmail (「転送されたメッセージ」) and Outlook (「差出人:」「送信日時:」「宛先:」「件名:」): not documented, and not checked against forwards from those products yet <!-- ja-ok: the forwarded-block lines of the Japanese interfaces -->
- The open questions of the mail design in [Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#to-verify)
