# Receiving

How Redmine AWS SES imports email that SES received: the addresses, how the project is chosen, the checks against spoofing and spam, and the options passed to Redmine's `MailHandler`. SES stores each message in the mail bucket (`inbound/<message ID>`) and starts the import; [Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#receiving) has the domain, the receipt rule and the bucket.

Checked against the Redmine 7.0.3 source on 2026-11-09, and against SES's documentation of the receipt notification on 2026-11-12 ([Contents of notifications for Amazon SES email receiving](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-notifications-contents.html), [Deliver to S3 bucket action](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-action-s3.html)).

## Addresses per project

| Address | Use |
| --- | --- |
| `<project identifier>@<domain>` | The project's address. Email sent to it becomes an issue in that project, and the project's notifications can be sent from it ([sending.md](sending.md#senders-per-project)) |
| `noreply@<domain>` (the default address) | Sender of email that does not belong to a project ("Default address" below) |

`<domain>` is Redmine's domain: the domain of the emission address (`Setting.mail_from`).

- **Identifiers and addresses:** A project's address is its identifier before the `@`; there are no other addresses per project. Redmine project identifiers consist of lowercase letters, digits, `-` and `_`, so they can be used as they are. A project whose identifier is longer than 64 characters (the limit of the part before `@`) cannot receive email, and its notifications keep the emission address.
- **Role addresses:** A project may use a role address (`postmaster`, `abuse`, `hostmaster`, `webmaster`, `mailer-daemon`, `root`, `admin`, `administrator`, `noreply`, `no-reply`, `security`, `support`; RFC 2142 and common ones), for example `support@` that an external mailbox forwards on purpose. Other mail servers send reports to some of them (bounces to `postmaster@`, abuse reports to `abuse@`), which then become issues too, so the "Email receiving" tab shows a warning for each project that receives email at one.
- **The default address:** A project whose identifier is the part before `@` of the default address does not receive email at it: the default address takes it. The tab shows a warning for it too.
- **The emission address:** Replies to notifications go to the emission address (`Setting.mail_from`). When it is not the default address, it takes email as the default address does (the same project, or not fetched), and the tab shows a warning, so that replies are not left as "Not fetched (no project)".
- **Whether to receive:** Each project chooses whether to receive email ("Receive email", default off). Email to a project that does not receive is dropped and recorded.
- **Project settings:** The "Email" tab of project settings sets whether to receive and the defaults ([admin.md](admin.md#project-email-settings)). The settings are in the plugin's table (`aws_ses_project_mail_settings`).

## Without addresses per project

When addresses per project are off (the default), email is received as standard Redmine does.

- **Receiving address:** Only the default address.
- **Choosing the project:** With Redmine's subaddress (`noreply+<identifier>@<domain>`). The plugin reads the subaddress from the envelope recipients, not from the `To` and `Cc` headers, so Bcc works too. Email without a subaddress is fetched into the default project or not fetched, as set in "Incoming emails" on the "Email receiving" tab.
- **Sender:** All notifications are sent from the default address.

<a id="address-for-the-whole-redmine"></a>

## Default address

Email that does not belong to a project is sent from the emission address (`Setting.mail_from`), the default address.

| Email sent from the default address | Redmine mailer method |
| --- | --- |
| Password reset (lost password) | `lost_password` |
| Account registration confirmation, activation request, activation notice | `register`<br>`account_activation_request`<br>`account_activated` |
| Account information (accounts created by an administrator) | `account_information` |
| Due date reminders (combining issues from several projects) | `reminder` |
| Security notifications, settings change notifications | `security_notification`<br>`settings_updated` |
| Test email | `test_email` |

The methods above are the Redmine 7.0.3 mailer methods that do not add the project header (`X-Redmine-Project`) (`app/models/mailer.rb`).

- **The part before `@`:** Set in "Default address" under "Receiving settings" on the "Email receiving" tab. The default is `noreply`, to match "Do not fetch", the default of "Incoming emails". When you switch to fetching, choose the part before `@` (for example `redmine`). An installation that has already saved the receiving settings keeps its value. A project with the same identifier cannot receive email at it.
- **Email sent to it:** "Incoming emails" chooses "Do not fetch" (default) or "Fetch into the default project". Replies to password resets and similar usually need not be fetched.

## Importing

The rake task `redmine_aws_ses:receive_mail` imports one message:

1. Lock the message's record (one run at a time per message, below). If the message was imported and its issue or note still exists, stop.
2. Find the message in the mail bucket (`HeadObject` on `inbound/`, or `processed/` for a re-import). A message larger than 40 MB is not imported: SES stores at most 40 MB, headers included ([Deliver to S3 bucket action](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-action-s3.html)); only its first 64 KiB are read, for the record's sender and subject, and it is recorded as "Not fetched (too large)".
3. Get the full message.
4. Decide, from the SES event and Redmine only: the verdicts ("Spoofing and spam" below), the project from the event's recipients (below), and whose message it is ("Forwarded email" below).
5. Pass the full message (or a member's forwarded original) and the options to Redmine's `MailHandler.safe_receive`, as Redmine's `rake redmine:email:read` does.
6. On success, move the message to `processed/` (`CopyObject`, then `DeleteObject`) after the record is saved. Each run leaves a record ([admin.md](admin.md#receiving-email)).

**One run at a time per message:** SES invokes the import asynchronously and may invoke it again, and "Fetch again" starts another run, so two runs for the same message can overlap. The run locks the message's record in a transaction (`SELECT … FOR UPDATE`), and the issue is created in the same transaction. Two first runs meet at the unique index of the message ID: the second fails, which rolls back the issue it created, and runs again on the first's record, where it stops. A serialization failure or a deadlock is retried once too. So one email never creates two issues.

**No nested transactions:** The import opens no transaction inside its own, so it works on databases without savepoints. When Redmine refuses a message, the whole transaction is rolled back, and the run starts again in a new one: a refused member's forward as the member's own message, a refused message as "Fetch error".

The task takes the values of the SES event as variables:

| Variable | From the SES event |
| --- | --- |
| `MESSAGE_ID` | `mail.messageId` (the key in the mail bucket) |
| `SES_RECIPIENTS` | `receipt.recipients` (the envelope recipients, comma-separated) |
| `SES_MAIL_FROM` | `mail.source` (the envelope MAIL FROM address), for registered forwarders ("Forwarded email" below). Optional: without it, no message counts as a forwarder's |
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
- **Attachments:** Attachments are saved as Redmine attachments (with [Redmine AWS S3](https://redmine-kit.github.io/redmine_aws_s3/), in S3).

## Spoofing and spam

Redmine decides which user an email comes from by the sender (`From`) address. If email with a forged sender is imported, an issue is created as that user. So the import checks the verdicts of the SES event:

| Verdict in the event (`receipt`) | Not `PASS` | Setting |
| --- | --- | --- |
| `virusVerdict.status` | Always dropped: the attachments would be served to everyone | — |
| `spamVerdict.status` | Dropped | "Also fetch spam" (`import_spam`, default off) |
| `dmarcVerdict.status` | Dropped | "Also fetch email failing DMARC" (`import_without_dmarc_pass`, default off) |

The values are `PASS`, `FAIL`, `GRAY` or `PROCESSING_FAILED`; a verdict that is missing counts as not `PASS`. `spfVerdict` decides only for registered forwarders ("Forwarded email" below); `dkimVerdict` and `dmarcPolicy` are recorded but do not decide. The verdicts are recorded whether or not the message is imported.

- **Why DMARC is required by default:** If DMARC passes, the sender's domain has been verified with SPF or DKIM. Email from Microsoft 365 or Gmail usually passes. Turning the setting on lets anyone send email in the name of a registered user.
- **From the SES event, never from headers:** The verdicts and the recipients come from the event, never from the message's headers (`X-SES-*`, `Authentication-Results`): a sender can add headers with the same names.
- **Without verdicts:** A message that has no verdicts (neither from the event nor from an earlier record) is dropped (`no_verdict`).
- **Re-imports:** The import record keeps the verdicts and the recipients, and a re-import uses them. The current settings apply.

<a id="forwarded-email"></a>

## Forwarded email

Email reaches a project in two forwarded ways: an external mailbox forwards everything it receives to the project's address (automatic forwarding), or a member forwards a customer's email from their mail client (forwarding by members). The decisions are made in one place in the code (`RedmineAws::SES::Admission`), from the SES event and Redmine only; the headers of the message decide nothing, as a sender can forge them.

### Automatic forwarding

For example, `support@company.example` on Google Workspace or Microsoft 365 forwards to `ecookbook@redmine.example.com`.

- **Project:** From the envelope recipients (`receipt.recipients`, "the envelope RCPT TO addresses"), which name the project's address, not from the `To` and `Cc` headers (`mail.destination`, "from the MIME headers"), which show `support@company.example`.
- **Author:** As for any email, the sender (`From`), through Redmine's rules (the project's "Unknown senders" setting and the sender's permissions), when the message passed DMARC. A message fetched only because a registered forwarder sent it (it failed DMARC) has a `From` that nothing authenticated, so its author follows "Author of forwarded email" (below).
- **DMARC:** Forwarding often makes DMARC fail: the forwarder sends from its own servers, so SPF does not align with the original sender's domain, and a forwarder that changes the message breaks its DKIM signature (a forward that keeps the message unchanged usually keeps the signature, and DMARC passes). For a message that fails DMARC, the project's "Forwarders" (addresses or domains) decide: the message is fetched only when SES's SPF verdict (`receipt.spfVerdict`) is `PASS` and the envelope sender (`mail.source`, "the envelope MAIL FROM address") is a registered forwarder's: the domain, or the address, also with a `+` tag. Otherwise it is not fetched ("Not fetched (DMARC fail)", or "Not fetched (forwarder SPF fail)" when the envelope sender is a forwarder's but SPF did not pass). "Also fetch email failing DMARC" still applies as before.
- **Why the envelope sender:** Forwarders that rewrite the envelope sender with the Sender Rewriting Scheme (SRS) put their own address in MAIL FROM, which SPF then checks for their domain. Microsoft 365 rewrites it for mailbox forwarding, Inbox rule redirection and mail flow rule redirection, as `<forwarding mailbox local part>+SRS=…@<forwarding mailbox domain>` (or `bounces+SRS=…@<default accepted domain>`, `bouncesEtr+SRS=…@<default accepted domain>`) ([Sender Rewriting Scheme (SRS) in Microsoft 365](https://learn.microsoft.com/en-us/exchange/reference/sender-rewriting-scheme)). Register the forwarding domain (`company.example`) so that every one of these matches.
- **What a registered forwarder trusts:** Registering a domain trusts everyone who can send with that envelope domain and pass SPF for it, that is, everyone who can send through the domain's mail servers. Register a domain only when it is your organization's own; register a shared provider (`gmail.com`, `outlook.com`, …) by the forwarding address, never by its domain. Only administrators change the forwarders.

**Microsoft 365:** In the Exchange admin center, go to **Recipients** > **Mailboxes**, select the mailbox, choose **Manage email forwarding** under **Email forwarding**, turn on **Forward all emails sent to this mailbox**, select **Forward to an external email address**, enter the project's address, and save; **Deliver message to both forwarding address and mailbox** keeps a copy ([Configure email forwarding for a mailbox in Exchange Online](https://learn.microsoft.com/en-us/exchange/recipients-in-exchange-online/manage-user-mailboxes/configure-email-forwarding)). Automatic forwarding to external addresses must be allowed by an anti-spam outbound policy ([Control automatic external email forwarding in Microsoft 365](https://learn.microsoft.com/en-us/defender-office-365/outbound-spam-policies-external-email-forwarding)). Register the forwarding mailbox's domain (and the default accepted domain, if it differs) as a forwarder.

**Google Workspace:** In the Google Admin console, go to **Apps** > **Google Workspace** > **Gmail** > **Routing**, and under **Email forwarding using recipient address map**, add a rule that maps the address (`support@company.example`) to the project's address ([Redirect or forward Gmail messages to another user](https://knowledge.workspace.google.com/admin/gmail/advanced/redirect-or-forward-gmail-messages-to-another-user)). Google's documentation does not say which envelope sender a forwarded message carries: send a test email that fails DMARC and check its result on the "Email receiving" tab before relying on a forwarder (see "To verify" in [setup.md](setup.md#to-verify)).

### Forwarding by members

A member forwards a customer's email to the project's address from their mail client. With the project's "Fetch email forwarded by members as the original" on (off by default), the issue is made from the original:

- **When it applies:** The sender is an active Redmine user with that address, whose message passed DMARC (so the address is really theirs), and who may add issues to the project. Otherwise the message is imported as a normal message from its sender.
- **Finding the original:** With `Fwd:`, `FW:` or `転送:` before the subject (a message with an attached `.eml` and no such subject is not a forward): a forwarded message attached as `message/rfc822` (forward as attachment), or the forwarded block in the body: Gmail's line `---------- Forwarded message ---------` (`---------- 転送されたメッセージ ---------`) before the original's `From:`, `Date:`, `Subject:` and `To:`, or Outlook's lines `From:`, `Sent:`, `To:`, `Subject:` (`差出人:`, `送信日時:`, `宛先:`, `件名:`). Only the outermost forward counts; a forward inside it stays in the body.
- **The issue:** The original's subject, body and attachments (the attachments of an inline forward are the forward's). The author follows "Author of forwarded email" (below). The `To` and `Cc` of an attached original become watchers as Redmine adds them, but with the member's permission ("Add watchers"), not the author's. The member is added as a watcher when they can see the issue. When they may add notes ("Add notes"), a note by the member, in Redmine's default language, says whose email was forwarded ("Forwarded the email from `<address>`.") and keeps the member's own text and the forward's own attachments (those besides the attached original), written the way Redmine writes the notes of commits (`init_journal`, then `save`): the issue's history shows who forwarded and when, without a custom field to set up.
- **Untrusted content:** The original is the content of the forward, which the member vouches for; Redmine's rules still apply to the original sender. The original's `In-Reply-To` and `References` are dropped, and an original whose subject refers to an issue or a message (`[… #123]`) is imported as the member's own message, so a forward never adds a note to another issue. The 40 MB limit applies to the original too.
- **Never lost:** A forward whose original cannot be found or read, or that Redmine refuses (for example an author without permission), is imported as the member's own message.

<a id="author-of-forwarded-email"></a>

### Author of forwarded email

The project's "Author of forwarded email" decides whose name a forwarded issue carries, for a member's forward and for a message fetched through a registered forwarder. Only administrators choose it, as only they choose "Create a user": the original sender's name is not authenticated (a member vouches for it, or only SPF of the forwarder passed).

| Setting | The original sender is the author when | Otherwise |
| --- | --- | --- |
| Senders outside the project (default) | They are an active Redmine user who is not an administrator and not a member of the project | The member who forwarded; for automatic forwarding, the anonymous user if the project fetches from unknown senders |
| Registered users | They are an active Redmine user | The same |
| Never the original sender | Never | The same |

- **Senders Redmine does not know:** With the first two settings, the issue is the anonymous user's when the project fetches from unknown senders ("Fetch as the anonymous user" or "Create a user"); otherwise the member's. No user is ever created from an original sender: "Create a user" does not apply to forwarded email.
- **Replies:** A message fetched through a registered forwarder may be a reply to a notification (by its subject `[… #123]`, `In-Reply-To` or `References`). Redmine adds such a reply to that issue or message, checking only the author's permissions; as nothing authenticated the `From`, the plugin lets it add a note only to an issue or a message of the project the envelope recipient chose, so customer replies forwarded from `support@` still reach their issues. A reply to another project is not fetched ("Not fetched (reply to another project)"). A member's forward never adds a note: the original's `In-Reply-To` and `References` are dropped, and an original whose subject names an issue or a message is imported as the member's own message.
- **No author:** A message fetched through a registered forwarder that no one may be the author of (for example, its sender is a member of the project, and the project does not fetch from unknown senders) is not fetched ("Not fetched (no author for forwarded email)").
- **Recorded:** For a message fetched through a registered forwarder, the list of received email shows the original sender (From). For a member's forward, it shows the member, who sent the message SES received; the member's note names the original sender.
- **Implementation:** The author is chosen in `RedmineAws::SES::Admission#author`; `RedmineAws::SES::ForwardedMailHandler`, a subclass of Redmine's `MailHandler`, puts it in place of the sender (overriding the private `dispatch`) and checks the member's permission for watchers (overriding the private `add_watchers`), both with `super`.

## Settings for receiving replies

| Setting | Value | Reason |
| --- | --- | --- |
| "Emission email address" in Redmine's administration settings | The default address (for example, `noreply@redmine.example.com`) | Also gives the plugin Redmine's domain |
| "Truncate emails after one of these lines" | A line before the quoted text (such as "--- Please write your reply above this line ---") | Keeps the quoted part of replies out of notes |

## Tests

| Target | What is checked |
| --- | --- |
| The verdicts | Each combination of the settings; a virus is never imported; missing verdicts |
| Importing | On the mail bucket in S3 (LocalStack or moto), with the values of an SES event (`test/fixtures/ses_event.json`): the project of the recipient, Bcc, a `Project:` keyword that cannot change the project, each reason for dropping, forged SES headers that change nothing, the move to `processed/`, re-imports from the record, the rake task, a message over the size limit, a second run and two first runs that create one issue, automatic forwarding through a registered forwarder, a member's forward and one Redmine refuses |
| Choosing the project | Addresses per project, identifiers longer than 64 characters, role addresses, projects that do not receive, the default address, subaddresses |
| Forwarded email | Table-driven: registered forwarders (domain, address, `+` tags, other domains), forged forwarder headers, DMARC failing without a registered forwarder, a forwarder whose SPF did not pass, a forwarder of another project; forwards by members with each condition alone not met (setting off, DMARC, permission, locked or unknown user, not a member); the originals of Gmail and Outlook in English and Japanese, forward as attachment, nested forwards, a block in another language, replies, two attached messages, an original over the size limit (`test/fixtures/forwarded/`) |
| Project settings | A project whose identifier cannot be an address shows no address and cannot turn "Receive email" on; only people with the permission can change the settings, and the permission alone opens project settings; the defaults must be the project's choices; only administrators can choose "Create a user"; parameters of an unexpected shape are ignored; errors are shown with Redmine's error list |
| Receiving settings | A part before `@` that cannot be an address is refused, and the page shows the error with the values given; parameters of an unexpected shape are ignored |
| Untrusted messages | Headers with raw 8-bit text (Shift_JIS without MIME encoding) and a date that is not one still leave a record |
