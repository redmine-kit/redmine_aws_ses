# Project email settings

When **Use per-project addresses** is on (**Administration** › **AWS** › **Email receiving**), each project receives email at its own address, its identifier before `@` on Redmine's domain, and the project's **Settings** get the **Email** tab. The tab is shown to the members whose role has **Manage email settings**, and to administrators.

## The Email tab

- **Email**: the project's address.
- **Receive email**: whether email to the address is fetched into the project.
- **Tracker**, **Category**, **Priority**, **Assignee** and **Private**: the values of the issues created from email.
- **Unknown senders**: what becomes of email from an address no Redmine user has: **Do not fetch**, **Fetch as the anonymous user**, or **Create a user**, which only administrators can choose.

## Forwarded email

Only administrators change these; members see them disabled.

- **Forwarders**: addresses or domains, one per line, that forward email to this project. Their email is fetched even when it fails DMARC, if SPF passes.
- **Forwarded email**: **Fetch email forwarded by members as the original** creates the issue from the original message, with the member as a watcher and a note by the member.
- **Author of forwarded email**: who may be the author of a forwarded message: **Senders outside the project**, **Registered users**, or **Never the original sender**.

## Permission

Give **Manage email settings** to roles in **Administration** › **Roles and permissions**. It is for members of the project only.
