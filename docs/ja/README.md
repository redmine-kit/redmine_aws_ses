# Redmine Serverless SES

Redmine Serverless SES(`redmine_serverless_ses`)は、Redmine のメールを Amazon SES で送受信するための Redmine のプラグインです。エラーの種類ごとの送信のやり直し、SES で受けたメールの取り込み、なりすましと迷惑メールの確認、プロジェクトごとのアドレスを持ちます。Redmine 本体のファイルは書き換えず、Redmine の標準の拡張の仕組みだけで作ります。今は開発の初期です(バージョン 0.1.1)。

- [導入](setup.md): 動作環境、インストール、設定、AWS のリソース、ネットワーク、テスト
- [IAM の権限](iam.md): 権限、ポリシーの例、リソースベースのポリシー
- [送信](sending.md): エラーの種類ごとのやり直し、送り直し、プロジェクトごとの送信元
- [受信](receiving.md): アドレス、取り込み、なりすましと迷惑メール
- [管理画面](admin.md): メールの送信、メールの受信、プロジェクトのメールの設定

<a id="features"></a>

## 機能

| 機能 | 中身 | 有効にする条件 | 資料 |
| --- | --- | --- | --- |
| メールの送信のやり直し | ジョブを動かすプロセスでの `raise_delivery_errors`、SES のエラーの種類ごとのやり直し(一時的なエラーはやり直し、アカウントの問題は送り直しのために残し、メッセージの問題は捨てる) | Lambda では `REDMINE_ROLE=worker`。Lambda 以外のときは、ジョブを動かすプロセス | [sending.md](sending.md) |
| メールの受信 | SES が S3 に置いたメールの取り込み(rake のタスク `redmine_serverless_ses:receive_mail`。中では Redmine の標準の `MailHandler` を使う)、SES のイベントの判定の確認(迷惑メールと DMARC は設定で選べ、ウイルスはいつも捨てる)、取り込みの記録 | 受信の設定がある | [receiving.md](receiving.md#importing) |
| プロジェクトごとのアドレス | プロジェクトごとの受信のアドレスと送信元、全体用のアドレス、プロジェクトの設定の「メール」のタブ | プラグインの設定で有効にする。無効なら Redmine の標準と同じ(送信元は 1 つで、プロジェクトはサブアドレス `redmine+識別子@…` で選ぶ) | [receiving.md](receiving.md#addresses-per-project) |
| 管理画面 | 共有の「Serverless」のメニューの「メールの送信」(SES の状態)と「メールの受信」のタブ、プロジェクトの設定の中のプロジェクトのメールの設定 | 管理者。使っていない機能の画面は出さない | [admin.md](admin.md) |

- **Lambda でも、Lambda 以外でも:** SES での送信(`aws-actionmailer-ses`)と受信は、SES と S3 に届く Redmine なら動きます。受信のタスクは、受けたメールのメッセージの ID を渡して動かします。AWS Lambda では、[Serverless](https://redmine-kit.github.io/serverless/ja/) が [Redmine Serverless SQS](https://redmine-kit.github.io/redmine_serverless_sqs/ja/) といっしょに入れます。メールを送るジョブを動かし、最後に失敗したものを記録して送り直せるようにするのは、Redmine Serverless SQS です。
- **gem とコードの分け方:** gem は `aws-actionmailer-ses`、`aws-sdk-sesv2`、`aws-sdk-s3` に依存します(チェックアウトでは、プラグインの `Gemfile` が足します)。`boot/redmine_serverless_ses.rb` は、`aws-actionmailer-ses`(配送の方法 `:ses_v2`)を読み込み、プロジェクトごとの送信元のためのインターセプターを登録します。プラグインは gem でもあるので、Bundler が Rails の初期化より前に読み込みます([setup.md](setup.md#installation))。ほかは Redmine が読み込む `lib/redmine_serverless_ses/`、`app/`、`db/` にあり、`init.rb` が有効にします。
- **テスト:** Redmine の標準の仕組みでテストを書き、Docker の中で moto といっしょに動かします([setup.md](setup.md#tests))。メールの取り込みのテストには、SES が足すヘッダーを付けたメールを使います([testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#email-redmine_serverless_ses))。
- **migration:** 受け取ったメールの記録(`serverless_received_mails`)と、プロジェクトのメールの設定(`serverless_project_mail_settings`)のテーブルを足します([admin.md](admin.md))。

<a id="sponsors"></a>

## スポンサー

<Sponsors><a href="https://www.keyselect.co.jp/">KEY SELECT</a> <a href="https://localstack.cloud">LocalStack</a></Sponsors>

<a id="license"></a>

## ライセンス

Redmine Serverless SES は、GNU General Public License バージョン 2 またはそれ以降のバージョンで公開しています。[LICENSE](../../LICENSE) を参照してください。Redmine の非公式のプラグインです。
