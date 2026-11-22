# Receiving email

With Redmine Kit AWS SES, Amazon SES receives the email sent to Redmine's domain and stores each message in an S3 bucket (`REDMINE_SES_MAIL_BUCKET`). Redmine then fetches the message with its own email receiving, which creates an issue or adds a note, and keeps a record of it. SES's verdicts decide which messages are fetched: messages with a virus never are. **Administration** › **AWS** › **Email receiving** shows the addresses, the received email and the receiving settings. Only administrators can open it.

## Email addresses

**Domain** (the domain of the **Emission email address**), **Default address** and **MX**, the MX record as it was last read (**Updated: …** at the top right; **Refresh** reads it again). With **Use per-project addresses**, a list shows each project's **Email** and whether it receives email (**Receive email**). A warning names the projects that receive email at a role address (such as `support@`) or at the default address. Without the bucket, a warning says that received email cannot be fetched.

## Received emails

The latest 100 messages, or only those **Not fetched**, with **Received**, **From**, **Subject**, **Project**, SES's **Verdicts** and the **Result**: the issue, **Fetched**, or why the message was not fetched (for example **Not fetched (DMARC fail)** or **Not fetched (no project)**). **Fetch again** fetches the checked messages again, in background jobs.

## Receiving settings

- **Default address**: the part before `@` of the address that takes email for the whole Redmine (`noreply` by default).
- **Incoming emails**: what becomes of email to the default address: **Do not fetch**, or **Fetch into the default project**, the project of **Default project**.
- **Fetched email**: **Also fetch email failing DMARC** and **Also fetch spam**, off by default.
- **Projects**: **Use per-project addresses** gives each project its own address (its identifier before `@`) and the project settings' **Email** tab; **Send notifications from project addresses** sends a project's notifications from its address.
