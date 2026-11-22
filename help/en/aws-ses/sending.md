# Sending email

Redmine Kit AWS SES sends Redmine's email through Amazon SES. **Administration** › **AWS** › **Email sending** shows the state of SES for Redmine's email. Only administrators can open it.

The tab shows the state as it was last read, with the time at the top right (**Updated: …**). A scheduled rake task (`redmine_kit:aws:ses:refresh`) reads it; **Refresh** reads it again at once. Opening the tab calls no AWS API.

## SES account

**Account status**, **Sending**, **Production access**, **Daily sending quota**, **Sent in the last 24 hours** and **Maximum send rate** of the SES account. **Send a test email** is Redmine's link that sends a test email to you. With Redmine Kit AWS SQS installed, **Failed jobs** opens its **Jobs** tab with the failed email jobs.

## Domain

The domain of Redmine's **Emission email address** (**Administration** › **Settings** › **Email notifications**), with **Verified** and its DKIM status in SES. When the emission email address has no domain, the tab asks to set it to an address on the domain verified in SES.

## Suppression list

The addresses SES does not send to, after a **Bounce** or a **Complaint**, with the Redmine user of the address. When a mailbox works again, **Remove** takes its address off the list.
