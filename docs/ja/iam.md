# IAM 権限

プロセスごとの、プラグインが自分で呼ぶ AWS の操作です。Lambda そのものの権限 (ログ、VPC の中での実行) は入れていません。ロールの全体は [Serverless の iam.md](https://redmine-kit.github.io/serverless/ja/iam.html) にあります。

<a id="permissions"></a>

## 権限

| 操作 | 対象 | 理由 |
| --- | --- | --- |
| `ses:SendEmail`<br>`ses:SendRawEmail` | サブドメインの SES の ID | メールを送るすべてのプロセス (テストメールを送る画面のリクエスト、ジョブ、rake)。SES v2 の `SendEmail` で、メール全体 (raw) を送る |
| `ses:GetEmailIdentity` | SES の ID | 画面のリクエスト。管理画面の「メール送信」 |
| `ses:GetAccount`<br>`ses:ListSuppressedDestinations`<br>`ses:DeleteSuppressedDestination` | `*` (絞れない) | 画面のリクエスト。同じ画面の、SES アカウント、サプレッションリストと、そこからの削除。`GetAccount` は、Redmine AWS の「ステータス」のタブの「接続テスト」の SES にも使う |
| `s3:GetObject`<br>`s3:DeleteObject` | メールのバケットの `inbound/*` | 取り込み (rake)。受け取ったメールを読み、移したあとに消す |
| `s3:PutObject` | メールのバケットの `processed/*` | 取り込み (rake)。取り込んだメールを移す (`processed/` への `CopyObject` のあと、`inbound/` で `DeleteObject`) |
| `s3:GetObject` | メールのバケットの `processed/*` | 取り込み済みのメールの再取得 (rake か、下のジョブ) |
| `inbound/*` と `processed/*` への `s3:GetObject`、`s3:DeleteObject`、`processed/*` への `s3:PutObject` | メールのバケット | ジョブ。「メール受信」の画面の「再取得」 |

<a id="example-policy"></a>

## ポリシーの例

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

SES が受け取ったメールを置けるようにする、バケットポリシーの文です (ほかのバケットと同じく、TLS でないリクエストを拒否する文も付けます)。

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

受信ルールが Lambda 関数を呼び出すときは、関数のリソースベースのポリシーで、`ses.amazonaws.com` に `lambda:InvokeFunction` を、同じ `aws:SourceAccount` と `aws:SourceArn` の条件で許します。関数は SES と同じリージョンに置きます ([Serverless の iam.md](https://redmine-kit.github.io/serverless/ja/iam.html#resource-based-policies))。

<a id="not-checked-yet"></a>

## 未確認の事項

- メッセージ全体を渡す SES v2 の `SendEmail` に、`ses:SendRawEmail` が要るか。
