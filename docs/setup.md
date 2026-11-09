# Setup

What a Redmine needs to use Redmine Serverless SES: installation, configuration, the SES and S3 resources, IAM permissions and network access. It works on AWS Lambda and on an ordinary server alike. [Serverless](https://redmine-kit.github.io/serverless/) sets all of this up with CloudFormation; this page is for setting it up by hand, or for checking what Serverless creates. The plugin is in the design stage, so the details below are the design and are checked when the code is written.

## Requirements

- Redmine 7.0 or later.
- A process that can reach SES and S3 with AWS credentials (an execution role on Lambda, an instance profile or a task role elsewhere). No access keys or SMTP passwords are stored in Redmine.
- For sending: the official AWS gem `aws-actionmailer-ses` (delivery method `:ses_v2`) ([Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#gems)).
- For retries of sending: jobs that run in a process of their own (on Lambda, `REDMINE_ROLE=worker`; [Redmine Serverless SQS](https://redmine-kit.github.io/redmine_serverless_sqs/) records the jobs that fail for the last time).

## Installation

**Getting the plugin:** with Docker, copy it from the plugin's image on ghcr.io, pinned by digest (tags: `main` and `sha-<commit>` for every push to `main`, `v*` for releases):

```dockerfile
COPY --from=ghcr.io/redmine-kit/redmine_serverless_ses:main@sha256:<digest> /redmine_serverless_ses plugins/redmine_serverless_ses/
```

Without Docker, clone the repository (`git clone https://github.com/redmine-kit/redmine_serverless_ses.git plugins/redmine_serverless_ses`) or, once releases are published, extract a release archive into `plugins/redmine_serverless_ses`.

1. Put the plugin in `plugins/redmine_serverless_ses` and run `bundle install` (Redmine's `Gemfile` loads the plugin's `Gemfile`).
2. Run `bin/rake redmine:plugins:migrate`. It creates the tables of received mail records (`serverless_received_mails`) and project mail settings (`serverless_project_mail_settings`).
3. Set sending in `config/configuration.yml`:

```yaml
production:
  email_delivery:
    delivery_method: :ses_v2
    ses_v2_settings:
      region: <region>
```

## Configuration

| Setting | Where | Contents |
| --- | --- | --- |
| Emission email address (`Setting.mail_from`) | Redmine's administration settings | The address for the whole Redmine, on the verified domain (for example `redmine@redmine.example.com`) ([Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#address-for-the-whole-redmine)) |
| Receiving settings | Plugin settings | The part before `@` of the address for the whole Redmine (default `redmine`), what to do with email sent to it, the default project ([admin.md](admin.md#receiving-email)) |
| Addresses per project | Plugin settings | On or off (default off, which is the same as standard Redmine). Per-project settings are in the "Email" tab of each project ([admin.md](admin.md#project-email-settings)) |
| Mail bucket | Environment variable | The bucket where SES stores received email. The variable name is decided when the code is written (not decided yet) |
| Truncate emails after one of these lines | Redmine's administration settings | A line before the quoted text, so that replies do not bring the quote into notes |

- **Retries only in the worker:** The plugin sets `raise_delivery_errors` to `true` only in the process that runs jobs (`REDMINE_ROLE=worker`), so that SES errors fail the job and are retried by kind ([Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#when-sending-fails)).
- **Importing:** The rake task `redmine_serverless_ses:receive_mail MESSAGE_ID=<message ID>` imports one received message. Something must start it for each message: on Lambda, the SES receipt rule invokes the task function asynchronously.

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

Redmine's standard plugin tests (`bin/rake redmine:plugins:test NAME=redmine_serverless_ses`). SES errors are raised one by one with the SDK's `stub_responses`, and the import tests use Redmine's test mail samples (`test/fixtures/mail_handler/`) with the headers SES adds ([Serverless testing.md](https://redmine-kit.github.io/serverless/testing.html#email-redmine_serverless_ses)).

## To verify

- Whether SES v2 `SendEmail` with the full message needs `ses:SendRawEmail`
- The service name of the interface endpoint for the SES API
- The open questions of the mail design in [Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#to-verify)
