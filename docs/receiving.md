# Receiving

How Redmine Serverless SES imports email that SES received: the addresses, how the project is chosen, the checks against spoofing and spam, and the options passed to Redmine's `MailHandler`. SES stores each message in the mail bucket (`inbound/<message ID>`) and starts the import; [Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#receiving) has the domain, the receipt rule and the bucket.

Checked against the Redmine 7.0.3 source on 2026-11-09.

## Addresses per project

| Address | Use |
| --- | --- |
| `<project identifier>@<domain>` | The project's address. Email sent to it becomes an issue in that project, and the project's notifications can be sent from it ([sending.md](sending.md#senders-per-project)) |
| `redmine@<domain>` (the address for the whole Redmine) | Sender of email that does not belong to a project ("Address for the whole Redmine" below) |

`<domain>` is Redmine's domain: the domain of the emission address (`Setting.mail_from`).

- **Identifiers and addresses:** A project's address is its identifier before the `@`; there are no other addresses per project. Redmine project identifiers consist of lowercase letters, digits, `-` and `_`, so they can be used as they are. A project cannot receive email, and its notifications keep the emission address, when its identifier:
  - is longer than 64 characters (the limit of the part before `@`),
  - is a role address that never goes to a project (`postmaster`, `abuse`, `hostmaster`, `webmaster`, `mailer-daemon`, `root`, `admin`, `administrator`, `noreply`, `no-reply`, `security`; RFC 2142 and common ones), or
  - is the part before `@` of the address for the whole Redmine, which that address takes.
- **Whether to receive:** Each project chooses whether to receive email (default: no). Email to a project that does not receive is dropped and recorded.
- **Project settings:** The "Email" tab of project settings sets whether to receive and the defaults ([admin.md](admin.md#project-email-settings)). The settings are in the plugin's table (`serverless_project_mail_settings`).

## Without addresses per project

When addresses per project are off (the default), email is received as standard Redmine does.

- **Receiving address:** Only the address for the whole Redmine.
- **Choosing the project:** With Redmine's subaddress (`redmine+<identifier>@<domain>`). The plugin reads the subaddress from the envelope recipients, not from the `To` and `Cc` headers, so Bcc works too. Email without a subaddress goes to the default project or is dropped, as set on the "Receiving email" tab.
- **Sender:** All notifications are sent from the address for the whole Redmine.

## Address for the whole Redmine

Email that does not belong to a project is sent from the emission address (`Setting.mail_from`), the address for the whole Redmine.

| Email sent from the address for the whole Redmine | Redmine mailer method |
| --- | --- |
| Password reset (lost password) | `lost_password` |
| Account registration confirmation, activation request, activation notice | `register`<br>`account_activation_request`<br>`account_activated` |
| Account information (accounts created by an administrator) | `account_information` |
| Due date reminders (combining issues from several projects) | `reminder` |
| Security notifications, settings change notifications | `security_notification`<br>`settings_updated` |
| Test email | `test_email` |

The methods above are the Redmine 7.0.3 mailer methods that do not add the project header (`X-Redmine-Project`) (`app/models/mailer.rb`).

- **The part before `@`:** Set on the "Receiving email" tab (default `redmine`; `noreply` is also possible). A project with the same identifier cannot receive email at it.
- **Email sent to it:** Put in the default project, or dropped (default). Replies to password resets and similar usually need not be imported.

## Importing

The rake task `redmine_serverless_ses:receive_mail` imports one message:

1. Check the verdicts of the SES event ("Spoofing and spam" below).
2. Choose the project from the event's recipients (below).
3. Get the full message from the mail bucket (`inbound/`, or `processed/` for a re-import).
4. Pass the full message and the options to Redmine's `MailHandler.safe_receive`, as Redmine's `rake redmine:email:read` does.
5. On success, move the message to `processed/` (`CopyObject`, then `DeleteObject`). Each run leaves a record ([admin.md](admin.md#receiving-email)).

The task takes the values of the SES event as variables:

| Variable | From the SES event |
| --- | --- |
| `MESSAGE_ID` | `mail.messageId` (the key in the mail bucket) |
| `SES_RECIPIENTS` | `receipt.recipients` (the envelope recipients, comma-separated) |
| `SES_SPAM_VERDICT`<br>`SES_VIRUS_VERDICT`<br>`SES_DMARC_VERDICT`<br>`SES_SPF_VERDICT`<br>`SES_DKIM_VERDICT` | `receipt.spamVerdict.status` and the others |
| `SES_DMARC_POLICY` | `receipt.dmarcPolicy` |

On Lambda, the SES receipt rule invokes the task function, whose handler sets these ([Serverless tasks.md](https://redmine-kit.github.io/serverless/tasks.html#kinds-of-events)). A re-import gives `MESSAGE_ID` only and uses what the first run recorded.

**Choosing the project:**

- **Recipients come from the SES event:** The envelope recipients (SMTP `RCPT TO`), not the `To` and `Cc` headers, so email received as Bcc is matched too. They are kept in the import record for re-imports.
- **Matching:** The recipient addresses on Redmine's domain are tried in order; the first that names a project that receives email (by its identifier) wins. If none does, the message is dropped and recorded.
- **Passing to Redmine:** The project's identifier and its defaults go in `MailHandler`'s options (`issue[:project]` and others). In Redmine's rules, a `Project:` keyword in the body would win, so `allow_override` is empty, and the keyword cannot change the project.
- **Replies:** Redmine adds replies to notification email to the original issue as notes, from the `In-Reply-To` and `References` headers (`MailHandler#dispatch`), whichever address the reply is sent to.

| Option | Value | Meaning |
| --- | --- | --- |
| `unknown_user` | The project's setting (default `ignore`) | Email from addresses not registered in Redmine |
| `no_permission_check` | `0` | The sender's permissions are checked |
| `allow_override` | Empty | Keywords in the body do not change the attributes |
| `issue[:project]` | The project chosen from the recipients | See above |
| `issue[:tracker]` and the other defaults | The project's defaults, by name | Values of created issues |

- **Auto-replies:** Email with `Auto-Submitted` (`auto-replied`, `auto-generated`) or `X-Autoreply: yes` (`MailHandler.ignored_emails_headers`) is dropped and recorded as an auto-reply. This prevents loops of notifications and imports.
- **Not imported by Redmine:** When `MailHandler` refuses a message (for example, an unregistered sender with `ignore`, or a sender without permission), it is recorded as not imported and stays in `inbound/`; Redmine's log has the reason.
- **Attachments:** Attachments are saved as Redmine attachments (with [Redmine Serverless S3](https://redmine-kit.github.io/redmine_serverless_s3/), in S3).

## Spoofing and spam

Redmine decides which user an email comes from by the sender (`From`) address. If email with a forged sender is imported, an issue is created as that user. So the import checks the verdicts of the SES event:

| Verdict in the event (`receipt`) | Not `PASS` | Setting |
| --- | --- | --- |
| `virusVerdict.status` | Always dropped: the attachments would be served to everyone | — |
| `spamVerdict.status` | Dropped | "Also fetch email marked as spam" (`import_spam`, default off) |
| `dmarcVerdict.status` | Dropped | "Also fetch email that fails DMARC" (`import_without_dmarc_pass`, default off) |

The values are `PASS`, `FAIL`, `GRAY` or `PROCESSING_FAILED`; a verdict that is missing counts as not `PASS`. `spfVerdict`, `dkimVerdict` and `dmarcPolicy` are recorded but do not decide. The verdicts are recorded whether or not the message is imported.

- **Why DMARC is required by default:** If DMARC passes, the sender's domain has been verified with SPF or DKIM. Email from Microsoft 365 or Gmail usually passes. Turning the setting on lets anyone send email in the name of a registered user.
- **From the SES event, never from headers:** The verdicts and the recipients come from the event, never from the message's headers (`X-SES-*`, `Authentication-Results`): a sender can add headers with the same names.
- **Without verdicts:** A message that has no verdicts (neither from the event nor from an earlier record) is dropped (`no_verdict`).
- **Re-imports:** The import record keeps the verdicts and the recipients, and a re-import uses them. The current settings apply.

## Settings for receiving replies

| Setting | Value | Reason |
| --- | --- | --- |
| "Emission email address" in Redmine's administration settings | The address for the whole Redmine (for example, `redmine@redmine.example.com`) | Also gives the plugin Redmine's domain |
| "Truncate emails after one of these lines" | A line before the quoted text (such as "--- Please write your reply above this line ---") | Keeps the quoted part of replies out of notes |

## Tests

| Target | What is checked |
| --- | --- |
| The verdicts | Each combination of the settings; a virus is never imported; missing verdicts |
| Importing | On the mail bucket in S3 (LocalStack or moto), with the values of an SES event (`test/fixtures/ses_event.json`): the project of the recipient, Bcc, a `Project:` keyword that cannot change the project, each reason for dropping, forged SES headers that change nothing, the move to `processed/`, re-imports from the record, the rake task |
| Choosing the project | Addresses per project, identifiers that cannot be an address (longer than 64 characters, role addresses), projects that do not receive, the address for the whole Redmine, subaddresses |
| Project settings | A project whose identifier cannot be an address shows no address and cannot turn receiving on; only people with the permission can change the settings |
