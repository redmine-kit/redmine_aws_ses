# Receiving email

Administration › AWS › **Email receiving** shows the **Email addresses** Redmine receives email at (the default address and each project's), the **Received emails** with SES's verdicts and what Redmine did with each message, and the **Receiving settings**: which messages to fetch (for example messages that fail DMARC or that SES marks as spam), the default project, and the projects' own addresses.

Messages SES finds a virus in are never fetched. The MX record is shown as it was last read (**Updated** at the top right; **Refresh** reads it again). A warning names the projects that receive email at a role address (such as `support@`) or at the default address.

Forwarded email: each project can register **Forwarders** whose email is fetched even when it fails DMARC, fetch a member's forward as its original, and choose the **Author of forwarded email**; only administrators change these (see the project's **Email** tab).

More: [Redmine AWS SES: administration pages](https://redmine-kit.github.io/redmine_aws_ses/admin.html) and [receiving email](https://redmine-kit.github.io/redmine_aws_ses/receiving.html).
