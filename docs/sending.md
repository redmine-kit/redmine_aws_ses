# Sending

How Redmine AWS SES sends Redmine's email through Amazon SES and what it does when sending fails. Sending uses the standard Rails mechanism: the ActionMailer delivery method `:ses_v2` of AWS's gem `aws-actionmailer-ses`, which calls SES v2 `SendEmail` with the full message (`content.raw`) and the recipients (To, Cc and Bcc) separately. Bcc recipients do not appear in the message. [Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#sending) has which functions send and the SES resources.

Checked against the Redmine 7.0.3 source and `aws-actionmailer-ses` 1.2.0 on 2026-11-09.

## Raising errors

Redmine's production settings (`production.rb`) have `raise_delivery_errors = false`, and Redmine's `Mailer.deliver_mail` swallows delivery errors unless `ActionMailer::Base.raise_delivery_errors` is true. Redmine's mail job (`Mailer::DeliveryJob`, a subclass of `ActionMailer::MailDeliveryJob`) fails only when an exception is raised; when the error is swallowed, the job succeeds and the queue does not retry it.

So the plugin sets `raise_delivery_errors` to `true` only in the process that runs jobs (`REDMINE_ROLE=worker`). `init.rb` runs after `production.rb`, so the setting holds. Other processes (web requests, rake tasks such as due date reminders) keep `false`, so that one failed message does not stop a whole task.

## Handling by kind of error

Errors from SES v2 `SendEmail` (the list in the API reference) are split into three kinds. The plugin adds a handler for SES errors to `Mailer::DeliveryJob` (`rescue_from`, declared after ActionMailer's own, so it is tried first).

| Error | Meaning | Handling |
| --- | --- | --- |
| `TooManyRequestsException`<br>`InternalFailure`<br>`ServiceUnavailable`<br>Other 5xx<br>Network errors | Temporary | Retried inside the job: up to 5 runs, after 3, 18, 83 and 258 seconds |
| `MessageRejected`<br>`BadRequestException` | A problem with the content or recipients of that message | The job is dropped. With [Redmine AWS SQS](https://redmine-kit.github.io/redmine_aws_sqs/), a failure record is kept |
| Anything else, such as:<br>`SendingPausedException`<br>`AccountSuspendedException`<br>`MailFromDomainNotVerifiedException`<br>`NotFoundException`<br>`LimitExceededException`<br>`AccessDeniedException` | A problem with the account or the settings. Every attempt fails until it is fixed | Raised without retries inside the job. The queue receives the message again and, after the last receive, moves it to the dead-letter queue, where Redmine AWS SQS records it |

- **Waits:** The waits are those of ActiveJob's `:polynomially_longer` without jitter (`executions⁴ + 2` seconds). They fit within the longest delay SQS allows (15 minutes). After the 5th run the error is raised, and the queue's retries and dead-letter queue apply as for account errors.
- **SDK retries:** The AWS SDK also retries 429 and 5xx by itself, before the job does (the default retry settings).
- **Two copies can arrive:** If the response is lost after SES accepts the message, a retry can send the same message twice.

## Sending again

1. **Get notified:** An alarm on the dead-letter queue or on the failure records tells you that email failed (in Serverless, a CloudWatch alarm).
2. **Fix the cause:** On the "Email sending" tab of the administration pages, check the SES account, the domain and the suppression list ([admin.md](admin.md#sending-email)).
3. **Send again:** Follow "Failed jobs" to Redmine AWS SQS's "Jobs" page, select the failed email and resend it, or move the dead-letter queue back ([its admin.md](https://redmine-kit.github.io/redmine_aws_sqs/admin.html#jobs)).

- **Failures after SES accepts the message:** Messages rejected by the recipient's mail server after SES accepted them (bounces) are not API errors. SES adds the address to the suppression list and stops sending to it; the "Email sending" tab shows the list.

## Senders per project

Redmine sends every notification from the emission address (`Setting.mail_from`). With addresses per project and per-project senders on ([receiving.md](receiving.md#addresses-per-project)), the plugin sends project notifications from the project's address.

- **How they are identified:** Redmine adds the project identifier in the `X-Redmine-Project` header to project notifications (issues, news, documents, files, forums, wiki) (`Mailer#redmine_headers`). An ActionMailer interceptor (the standard Rails mechanism that rewrites email before sending; registered by `boot/`) reads it and changes the sender to `<identifier>@<domain>`.
- **Display name:** Redmine's display name (the author's name, when the emission address has none) is kept.
- **Email without the header:** Email that does not belong to a project keeps the emission address, the default address ([receiving.md](receiving.md#address-for-the-whole-redmine)).
- **Projects that do not receive email:** The sender is the project's address, but replies would not be imported, so `Reply-To` is the emission address.
- **Optional:** Off by default. "Send notifications from project addresses" in "Receiving settings" on the "Email receiving" tab turns it on.

## Tests

| Target | What is checked |
| --- | --- |
| Sending through SES | A notification is sent through `aws-actionmailer-ses` to SES v2 (LocalStack, or moto without its token). A sender that is not a verified identity raises `MessageRejected` in the worker (a mocked answer, below) |
| Connection test | SES v2 `GetAccount` (a mocked answer, below) |
| Errors by kind | Each `SendEmail` error raised one by one with SDK response stubs: temporary errors are retried in the job and raised after the last run, message errors are dropped, account errors are raised for the queue |
| Only in the worker | `raise_delivery_errors` is set only with `REDMINE_ROLE=worker` |
| Senders per project | The interceptor changes the sender and `Reply-To` only when the settings are on |
