# Administration pages

These are the administration pages of Redmine Serverless SES. Only Redmine administrators can open them (`require_admin`), except the project email settings, which people with the project permission that the plugin adds can also change (below). The pages are the "Sending email" and "Receiving email" tabs under the "Serverless" item of Redmine's administration menu, which all the Redmine Serverless plugins share, whether or not [Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/admin.html#the-serverless-menu) is installed. The project email settings are a tab in project settings instead.

The specifications in this page were checked against official information and the Redmine 7.0.3 source as of 2026-11-08. Sources are in [sources.md](https://redmine-kit.github.io/serverless/sources.html).

- **No secrets shown:** AWS credentials and the bodies of received email are not shown. State from SES and the MX record are cached for 1 minute.
- **Settings on the page:** Receiving options are plugin settings (Redmine's `Setting.plugin_redmine_serverless_ses`, stored in the database) and are changed on the "Receiving email" tab. The plugin list has no "Configure" link.
- **Operations are logged:** Removing an address from the suppression list, re-importing and changing settings are written to Redmine's log with who did what (`[redmine_serverless_ses] <login> ...`).
- **Connection check:** When Redmine Serverless is installed, its connection check also calls SES v2 `GetAccount`.

## Sending email

| Item | Contents | Source |
| --- | --- | --- |
| Account status | Production access (out of the sandbox), whether sending is enabled, enforcement status | SES v2 `GetAccount` |
| Sending limits | 24-hour limit, per-second limit, number sent in the last 24 hours | Same as above |
| Sender domain | Whether the domain of the emission address in the administration settings is verified, DKIM status | SES v2 `GetEmailIdentity` |
| Suppression list | Addresses SES has stopped sending to (added because of bounces and complaints), with the Redmine users who have them. The first 100 | SES v2 `ListSuppressedDestinations` |
| Removing from the suppression list | A button per address, after confirmation | SES v2 `DeleteSuppressedDestination` |
| Test email | A link to Redmine's standard "Send a test email" (in "Email notifications" under Administration › Settings). The same feature is not added | — |
| Failed email | When Redmine Serverless SQS is installed, a link to the list of failed email only on its "Jobs" page | — |

- **Why show the suppression list:** Once an address bounces, SES stops sending to it. From Redmine it looks as if the email was sent, so when someone says "notifications do not arrive", this page lets you check.
- **Test email:** Redmine's standard test email is sent within the page request (`deliver_now`), so `redmine-web` is also given permission to send through SES ([mail.md](https://redmine-kit.github.io/serverless/mail.html#ses)).

## Receiving email

| Item | Contents | Source |
| --- | --- | --- |
| Addresses | Redmine's domain (the domain of the emission address), the address for the whole Redmine, and the projects' addresses (whether they receive) | Plugin settings and project email settings |
| MX record | The MX hosts of Redmine's domain, to check that they are the SES receiving endpoint | DNS lookup, with a 2-second timeout |
| Received email | Time received, sender, subject, project, SES's verdicts (virus, spam, DMARC), result (the issue, or the reason it was dropped). The newest 100; dropped email can be listed on its own | The plugin's table (below) |
| Re-import | Imports the selected messages again | A job for each message (`ServerlessReimportMailJob`; SQS in Serverless, where `redmine-worker` imports it) |
| Receiving settings | The address for the whole Redmine (the part before `@`), email sent to it (drop, or put in the default project), the default project, importing email that fails DMARC, importing spam (both off by default, with an explanation on the page; viruses are always dropped), addresses per project, per-project senders | Plugin settings (changed on the page). Email that fails DMARC is dropped regardless of settings ([receiving.md](receiving.md#spoofing-and-spam)) |

- **Import records:** `redmine_serverless_ses:receive_mail` stores the result for each message in the plugin's table (`serverless_received_mails`): the sender, the subject, the envelope recipients and the verdicts from the SES event, the project, and the issue created or the note added. The body is not stored; its key in the mail bucket (`inbound/` or `processed/`) is. A re-import updates the same record. Records older than 90 days are deleted by `rake redmine_serverless_ses:prune_records`, which Serverless runs daily ([security.md](https://redmine-kit.github.io/serverless/security.html#retention-periods)).
- **Reasons for dropping:** no verdicts from SES (a message that was never received through the event), virus, spam, DMARC failure, auto-reply, no project receives it, or not imported by Redmine (for example, a sender that is not registered, or without permission; Redmine's log has the reason). Dropped email stays in `inbound/` and can be re-imported after the cause is fixed.
- **Re-import:** The page does not call `redmine-task` directly; it puts a job on the queue. This way `redmine-web` needs no permission to read the mail bucket or to invoke Lambda. With Redmine Serverless SQS, the job class is added to the allowed job classes.
- **Why receiving settings are on the page:** You do not have to deploy each time you change the default project. `redmine_serverless_ses:receive_mail` reads the settings from the database on every run.

## Project email settings

An "Email" tab is added to project settings when addresses per project are on. It configures the address per project ([receiving.md](receiving.md#addresses-per-project)). The settings are in the plugin's table (`serverless_project_mail_settings`), because Redmine's settings are for the whole Redmine only (`Setting`, a name and a value) and Redmine has no table for per-project settings. Deleting a project deletes its row.

| Item | Contents |
| --- | --- |
| Address | `<identifier or alias>@<Redmine's domain>`. Display only. A project whose identifier is longer than 64 characters needs an alias |
| Whether to receive email | Do not receive (default) or receive |
| Alias | An address other than the identifier (the part before `@`: lowercase letters, digits, `.`, `_` and `-`). It cannot be saved if it matches another project's identifier or alias, the address for the whole Redmine, or a reserved name (`postmaster`, `abuse`, `hostmaster`, `webmaster`, `mailer-daemon`, `root`, `admin`, `administrator`, `noreply`, `no-reply`, `security`) |
| Default values | Tracker, category, priority, assignee of created issues, and whether they are private |
| Handling unregistered addresses | Do not import (default), accept as the anonymous user, or create an account (Redmine's `unknown_user` values `ignore`, `accept`, `create`) |

- **Who can change it:** Redmine administrators and members with the project permission "Manage email settings" that the plugin adds.
- **When accepting unregistered addresses:** Use this to receive email from outside people, such as for a contact desk. Spam increases, so keep the DMARC check ([receiving.md](receiving.md#spoofing-and-spam)).

## Permissions

For these pages, the role that runs Redmine's web requests gets permission to read SES status and to remove addresses from the suppression list. The list and an example policy are in [iam.md](iam.md).

## Tests

Each page has Redmine functional tests, with SDK response stubs for SES ([testing.md](https://redmine-kit.github.io/serverless/testing.html#administration-pages)).
