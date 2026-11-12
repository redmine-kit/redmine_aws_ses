# IAM permissions

The plugin's own calls to AWS, by the process. Lambda's own permissions (logs, running in a VPC) are not included; [Serverless iam.md](https://redmine-kit.github.io/serverless/iam.html) has the full roles.

## Permissions

| Action | Resource | Why |
| --- | --- | --- |
| `ses:SendEmail`<br>`ses:SendRawEmail` | The SES identity of the subdomain | Every process that sends email (web requests for test email, jobs, rake): sending the full message (raw) with SES v2 `SendEmail` |
| `ses:GetEmailIdentity` | The SES identity | The process that runs `rake redmine_aws_ses:refresh` (on a schedule) and web requests ("Refresh" on the email tabs): reading the domain's state for the tabs ([setup.md](setup.md#refreshing-the-ses-state)) |
| `ses:GetAccount`<br>`ses:ListSuppressedDestinations`<br>`ses:DeleteSuppressedDestination` | `*` (cannot be scoped) | The same processes: the account status and the suppression list; web requests also remove an address from it (`DeleteSuppressedDestination`). `GetAccount` is also the SES check in the "Connection test" on the "Status" tab of Redmine AWS |
| `s3:GetObject`<br>`s3:DeleteObject` | `inbound/*` in the mail bucket | The import (rake): reading received email (`HeadObject` for its size, which `s3:GetObject` allows, then `GetObject`), removing it after the move |
| `s3:PutObject` | `processed/*` in the mail bucket | The import (rake): moving imported email (`CopyObject` to `processed/`, then `DeleteObject` in `inbound/`) |
| `s3:GetObject` | `processed/*` in the mail bucket | Re-importing a message that was already imported (rake, or the job below) |
| `s3:GetObject` on `inbound/*` and `processed/*`, `s3:DeleteObject` on `inbound/*` only (a message moves from there), `s3:PutObject` on `processed/*` | The mail bucket | Jobs: "Fetch again" on the "Email receiving" page |

## Example policy

For the process that imports email:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Send",
      "Effect": "Allow",
      "Action": ["ses:SendEmail", "ses:SendRawEmail"],
      "Resource": "arn:aws:ses:<region>:<account>:identity/<domain>"
    },
    {
      "Sid": "ReadReceived",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::<mail bucket>/inbound/*"
    },
    {
      "Sid": "MoveImported",
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::<mail bucket>/processed/*"
    },
    {
      "Sid": "ReadImported",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::<mail bucket>/processed/*"
    }
  ]
}
```

## Resource-based policies

Bucket policy statement that lets SES store received email (with the TLS-only deny as in other buckets):

```json
{
  "Sid": "SesStoresReceivedEmail",
  "Effect": "Allow",
  "Principal": { "Service": "ses.amazonaws.com" },
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::<mail bucket>/inbound/*",
  "Condition": {
    "StringEquals": { "aws:SourceAccount": "<account>" },
    "ArnLike": { "aws:SourceArn": "arn:aws:ses:<region>:<account>:receipt-rule-set/<rule set>:receipt-rule/<rule>" }
  }
}
```

When the receipt rule invokes a Lambda function, the function's resource-based policy allows `lambda:InvokeFunction` by `ses.amazonaws.com` with the same `aws:SourceAccount` and `aws:SourceArn` conditions. The function must be in the same Region as SES ([Serverless iam.md](https://redmine-kit.github.io/serverless/iam.html#resource-based-policies)).

## Not checked yet

- Whether SES v2 `SendEmail` with the full message needs `ses:SendRawEmail`.
