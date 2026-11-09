# 準備

Redmine Serverless SES を使う Redmine に要るもの(インストール、設定、SES と S3 のリソース、IAM の権限、ネットワーク)です。AWS Lambda でも、ふつうのサーバーでも同じです。[Serverless](https://redmine-kit.github.io/serverless/ja/) は、これを CloudFormation でまとめて作ります。このページは、手で用意するときや、Serverless が作るものを確認するときのためのものです。プラグインは設計段階なので、下の内容は設計で、コードを書くときに確認します。

<a id="requirements"></a>

## 前提

- Redmine 7.0 以降。
- AWS の認証情報で SES と S3 に届くプロセス(Lambda では実行ロール、ほかではインスタンスプロファイルやタスクのロール)。Redmine にアクセスキーや SMTP のパスワードは置きません。
- 送信には、AWS の公式の gem `aws-actionmailer-ses`(配送の方法は `:ses_v2`)([Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#gems))。
- 送信のやり直しには、別のプロセスで動くジョブ(Lambda では `REDMINE_ROLE=worker`。最後まで失敗したジョブは [Redmine Serverless SQS](https://redmine-kit.github.io/redmine_serverless_sqs/ja/) が記録します)。

<a id="installation"></a>

## インストール

**プラグインの取り方:** Docker なら、ghcr.io のプラグインのイメージから、digest で固定して写します(タグは、`main` への push のたびに `main` と `sha-<コミット>`、リリースは `v*`)。

```dockerfile
COPY --from=ghcr.io/redmine-kit/redmine_serverless_ses:main@sha256:<digest> /redmine_serverless_ses plugins/redmine_serverless_ses/
```

Docker を使わないなら、リポジトリを clone するか(`git clone https://github.com/redmine-kit/redmine_serverless_ses.git plugins/redmine_serverless_ses`)、リリースを公開したあとは、そのアーカイブを `plugins/redmine_serverless_ses` に展開します。

1. プラグインを `plugins/redmine_serverless_ses` に置き、`bundle install` を実行します(プラグインの `Gemfile` は Redmine の `Gemfile` が読み込みます)。
2. `bin/rake redmine:plugins:migrate` を実行します。受け取ったメールの記録(`serverless_received_mails`)と、プロジェクトのメールの設定(`serverless_project_mail_settings`)の表ができます。
3. `config/configuration.yml` に送信を設定します。

```yaml
production:
  email_delivery:
    delivery_method: :ses_v2
    ses_v2_settings:
      region: <region>
```

<a id="configuration"></a>

## 設定

| 設定 | 置き場所 | 中身 |
| --- | --- | --- |
| 送信元メールアドレス(`Setting.mail_from`) | Redmine の管理画面の設定 | Redmine 全体のアドレス。確認済みのドメインのもの(例: `redmine@redmine.example.com`)([Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#address-for-the-whole-redmine)) |
| 受信の設定 | プラグインの設定 | Redmine 全体のアドレスの `@` の前(既定は `redmine`)、そこに届いたメールの扱い、既定のプロジェクト([admin.md](admin.md#receiving-email)) |
| プロジェクトごとのアドレス | プラグインの設定 | 使うか使わないか(既定は使わない。Redmine の標準と同じ)。プロジェクトごとの設定は、各プロジェクトの「メール」のタブ([admin.md](admin.md#project-email-settings)) |
| メールのバケット | 環境変数 | SES が受け取ったメールを置くバケット。変数の名前は、コードを書くときに決める(未定) |
| 「この行以降を切り捨てる」 | Redmine の管理画面の設定 | 引用の前の行。返信の引用が注記に入らないようにする |

- **やり直しは worker だけ:** プラグインは、ジョブを動かすプロセス(`REDMINE_ROLE=worker`)でだけ `raise_delivery_errors` を `true` にします。SES のエラーでジョブが失敗し、種類ごとにやり直されるようにするためです([Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#when-sending-fails))。
- **取り込み:** rake のタスク `redmine_serverless_ses:receive_mail MESSAGE_ID=<メッセージ ID>` が、受け取ったメールを 1 通取り込みます。メールごとに、何かがこれを起動する必要があります。Lambda では、SES の受信のルールがタスクの関数を非同期で呼びます。

<a id="aws-resources"></a>

## AWS のリソース

| リソース | 設定 |
| --- | --- |
| SES のドメインの ID | Redmine のサブドメイン(例: `redmine.example.com`)。使うリージョンで、Easy DKIM で確認する。送信と受信の両方に使う |
| SES の本番の利用 | 前もって申請する(サンドボックスを出る)。リージョンごと |
| DNS | サブドメインの MX を SES の受信のエンドポイント(`inbound-smtp.<region>.amazonaws.com`、優先度 10)に向け、Easy DKIM の CNAME を置く([Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#receiving-domain)) |
| 受信のルール | リージョンの有効なルールセットの中。受信者はサブドメイン。TLS は必須。迷惑メールとウイルスの検査は有効。1 つめのアクションで、メールのバケットの `inbound/` に置く。2 つめのアクションで、取り込みを起動する(Lambda では、タスクの関数を非同期で呼ぶ)([Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#receipt-rules)) |
| メールのバケット | `inbound/`(受け取ったもの)と `processed/`(取り込んだもの)。どちらもライフサイクルで 30 日で消す。バケットポリシーで、`inbound/` には SES だけが書けるようにし、TLS でない要求を拒む |

<a id="iam-permissions"></a>

## IAM の権限

プラグインに要る権限と例のポリシーは、[iam.md](iam.md) にあります。

<a id="network"></a>

## ネットワーク

| どこから | どこへ | インターネットに出られない VPC の中では |
| --- | --- | --- |
| Redmine | SES v2 の API(`SendEmail`、管理画面) | SES の API のインターフェースのエンドポイントか、NAT インスタンス。エンドポイントのサービスの名前は、作るときに確認する(未確認) |
| Redmine | S3(メールのバケット) | S3 のゲートウェイのエンドポイント(`com.amazonaws.<region>.s3`) |
| 送り手 | SES の受信(SMTP) | VPC の外。SES が受け取る |

<a id="tests"></a>

## テスト

Redmine の標準のプラグインのテスト(`bin/rake redmine:plugins:test NAME=redmine_serverless_ses`)です。SES のエラーは SDK の `stub_responses` で 1 つずつ起こし、取り込みのテストは、SES が足すヘッダーを付けた Redmine のテスト用のメール(`test/fixtures/mail_handler/`)を使います([Serverless の testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#email-redmine_serverless_ses))。

<a id="to-verify"></a>

## 確認すること

- メッセージ全体を渡す SES v2 の `SendEmail` に、`ses:SendRawEmail` が要るか
- SES の API のインターフェースのエンドポイントのサービスの名前
- メールの設計の、[Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#to-verify) にある項目
