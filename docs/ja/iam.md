# IAM の権限



<a id="permissions"></a>

## 権限

| 操作 | 対象 | 理由 |
| --- | --- | --- |
| `ses:SendEmail`、`ses:SendRawEmail` | サブドメインの SES の ID | メールを送るすべてのプロセス(テストのメールのための画面の要求、ジョブ、rake)。SES v2 の `SendEmail` で、メール全体(raw)を送る |
| `ses:GetEmailIdentity` | SES の ID | 画面の要求。管理画面の「メールの送信」 |
| `ses:GetAccount`、`ses:ListSuppressedDestinations`、`ses:DeleteSuppressedDestination` | `*`(絞れない) | 画面の要求。同じ画面の、アカウントの状態、サプレッションリストと、そこからの削除。`GetAccount` は、Redmine Serverless の「状態と接続」の SES の確認にも使う |
| `s3:GetObject`、`s3:DeleteObject` | メールのバケットの `inbound/*` | 取り込み(rake)。受け取ったメールを読み、移したあとに消す |
| `s3:PutObject` | メールのバケットの `processed/*` | 取り込み(rake)。取り込んだメールを移す |
| `inbound/*` と `processed/*` への `s3:GetObject`、`s3:DeleteObject`、`processed/*` への `s3:PutObject` | メールのバケット | ジョブ。「メールの受信」の画面からの取り込み直し |

<a id="example-policy"></a>

## 例のポリシー

メールを取り込むプロセスのポリシーです。

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

<a id="resource-based-policies"></a>

## リソースベースのポリシー

SES が受け取ったメールを置けるようにする、バケットポリシーの文です(ほかのバケットと同じく、TLS でない要求を拒む文も付けます)。

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

- **Lambda:** 受信のルールが Lambda の関数を呼ぶときは、関数のリソースベースのポリシーで、`ses.amazonaws.com` に `lambda:InvokeFunction` を、同じ `aws:SourceAccount` と `aws:SourceArn` の条件で許します。関数は SES と同じリージョンに置きます([Serverless の iam.md](https://redmine-kit.github.io/serverless/ja/iam.html#resource-based-policies))。

<a id="not-checked-yet"></a>

## 未確認のこと

- メッセージ全体を渡す SES v2 の `SendEmail` に、`ses:SendRawEmail` が要るか。
