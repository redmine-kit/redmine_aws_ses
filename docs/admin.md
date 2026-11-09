# Administration pages

This is the design of the administration pages of Redmine Serverless SES. Only Redmine administrators can open them (`require_admin`), except the project email settings, which people with the project permission that the plugin adds can also open (below). The pages are the "Sending email" and "Receiving email" tabs under the "Serverless" item of Redmine's administration menu, which all the Redmine Serverless plugins share, whether or not [Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/admin.html#the-serverless-menu) is installed. The project email settings are a tab in project settings instead.

The specifications in this page were checked against official information and the Redmine 7.0.3 source as of 2026-11-08. Sources are in [sources.md](https://redmine-kit.github.io/serverless/sources.html).

- **No secrets shown:** AWS credentials are not shown. State from SES is cached for 1 minute, and heavy checks run when a button is pressed.
- **Settings on the page:** Receiving options are plugin settings (Redmine's `Setting.plugin_*`, stored in the database) and are changed on the page.
- **Connection check:** When Redmine Serverless is installed, its connection check also calls SES v2 `GetAccount`.

## Sending email

| Item | Contents | Source |
| --- | --- | --- |
| Account status | Production access (out of the sandbox), whether sending is enabled, enforcement status | SES v2 `GetAccount` |
| Sending limits | 24-hour limit, per-second limit, number sent in the last 24 hours | Same as above |
| Sender domain | Whether the domain of the emission address in the administration settings is verified, DKIM status | SES v2 `GetEmailIdentity` |
| Suppression list | List of addresses SES has stopped sending to (added because of bounces and complaints), matched against Redmine users' addresses | SES v2 `ListSuppressedDestinations` |
| Removing from the suppression list | A button removes an address from the list | SES v2 `DeleteSuppressedDestination` |
| Test email | A link to Redmine's standard "Send a test email" (in "Email notifications" under Administration › Settings). The same feature is not added | — |
| Failed email | When Redmine Serverless SQS is installed, a link to the list of failed email only on its "Jobs" page | — |

- **Why show the suppression list:** Once an address bounces, SES stops sending to it. From Redmine it looks as if the email was sent, so when someone says "notifications do not arrive", this page lets you check.
- **Test email:** Redmine's standard test email is sent within the page request (`deliver_now`), so `redmine-web` is also given permission to send through SES ([mail.md](https://redmine-kit.github.io/serverless/mail.html#ses)).

## Receiving email

| Item | Contents | Source |
| --- | --- | --- |
| Receiving addresses | Redmine's subdomain, the global address, and the list of addresses per project (whether they receive, aliases) | Plugin settings and project email settings |
| MX record | Whether the MX of the receiving host name points to the SES receiving endpoint | DNS lookup (internet names are resolved with Lambda's default DNS) |
| Received email | Time received, sender, subject, result (issue created, note added, reason dropped) | The plugin's table (below) |
| Re-import | Import dropped or failed email again | Put an import job on the job queue (SQS in Serverless; `redmine-worker` imports it) |
| Receiving settings | The global address (the part before `@`), how to handle email sent to the global address (put it in the default project, or drop it), whether to use per-project senders | Plugin settings (changed on the page). Email that fails DMARC is dropped regardless of settings ([mail.md](https://redmine-kit.github.io/serverless/mail.html#spoofing-and-spam)) |

- **Import records:** `redmine_serverless_ses:receive_mail` stores the result for each email (including the recipient and the project it was matched to) in the plugin's table (`serverless_received_mails`). The email body is not stored; its location in S3 (the key in `inbound/` or `processed/`) is. Records are deleted after 90 days ([security.md](https://redmine-kit.github.io/serverless/security.html#retention-periods)).
- **Reasons for dropping:** One of: virus, spam, DMARC failure, unregistered address, auto-reply, or a Redmine import error. This page lets you check whether email with a forged sender is arriving.
- **Re-import:** The page does not call `redmine-task` directly; it puts a job on SQS. This way `redmine-web` does not need permission to invoke Lambda.
- **Why receiving settings are on the page:** You do not have to deploy each time you change the default project. `redmine_serverless_ses:receive_mail` reads the settings from the database on every run.

## Project email settings

An "Email" tab is added to project settings. It configures the address per project ([mail.md](https://redmine-kit.github.io/serverless/mail.html#addresses-per-project)).

| Item | Contents |
| --- | --- |
| Address | `<identifier>@<Redmine's subdomain>`. Display only |
| Whether to receive email | Do not receive (default) or receive |
| Alias | An address other than the identifier (the part before `@`). It cannot be saved if it matches another project's identifier or alias, or a reserved name |
| Default values | Tracker, category, priority, assignee of created issues, and whether they are private |
| Handling unregistered addresses | Do not import (default), accept as the anonymous user, or create an account (Redmine's `unknown_user` values `ignore`, `accept`, `create`) |

- **Who can open it:** Redmine administrators and people with the project permission "Manage email settings" that the plugin adds.
- **When accepting unregistered addresses:** Use this to receive email from outside people, such as for a contact desk. Spam increases, so do not turn off the DMARC check ([mail.md](https://redmine-kit.github.io/serverless/mail.html#spoofing-and-spam)).

## Permissions

For these pages, the role that runs Redmine's web requests gets permission to read SES status and to remove addresses from the suppression list. The list and an example policy are in [iam.md](iam.md).

## Tests

Each page has Redmine functional tests and system tests ([testing.md](https://redmine-kit.github.io/serverless/testing.html#administration-pages)).
