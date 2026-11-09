# IAM permissions



## Permissions

| Action | Resource | Why |
| --- | --- | --- |
| `ses:SendEmail`, `ses:SendRawEmail` | The SES identity of the subdomain | Every process that sends email (web requests for test email, jobs, rake): sending the full message (raw) with SES v2 `SendEmail` |
| `ses:GetEmailIdentity` | The SES identity | Web requests: the "Sending email" administration page |
| `ses:GetAccount`, `ses:ListSuppressedDestinations`, `ses:DeleteSuppressedDestination` | `*` (cannot be scoped) | Web requests: the same page (account status, the suppression list and removing an address from it). `GetAccount` is also the SES check on Redmine Serverless's "Status and connections" |
| `s3:GetObject`, `s3:DeleteObject` | `inbound/*` in the mail bucket | The import (rake): reading received email, removing it after the move |
| `s3:PutObject` | `processed/*` in the mail bucket | The import (rake): moving imported email |
| `s3:GetObject`, `s3:DeleteObject` on `inbound/*` and `processed/*`, `s3:PutObject` on `processed/*` | The mail bucket | Jobs: re-importing from the "Receiving email" page |

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

- **Lambda:** When the receipt rule invokes a Lambda function, the function's resource-based policy allows `lambda:InvokeFunction` by `ses.amazonaws.com` with the same `aws:SourceAccount` and `aws:SourceArn` conditions. The function must be in the same Region as SES ([Serverless iam.md](https://redmine-kit.github.io/serverless/iam.html#resource-based-policies)).

## Not checked yet

- Whether SES v2 `SendEmail` with the full message needs `ses:SendRawEmail`.
