# Redmine AWS SES

Redmine AWS SES (`redmine_aws_ses`) は、Redmine のメールを Amazon SES で送受信するための Redmine のプラグインです。エラーの種類に応じた送信の再試行、SES で受信したメールの取り込み、なりすましとスパムの確認、プロジェクトごとのアドレスを持ちます。[Redmine AWS](https://redmine-kit.github.io/redmine_aws/ja/) (`redmine_aws`) が必要です。Redmine 本体のファイルは書き換えず、Redmine 標準の拡張のしくみだけで作ります。今は開発の初期です。

- [導入](setup.md): 動作環境、インストール、設定、AWS リソース、ネットワーク、テスト
- [IAM 権限](iam.md): 権限、ポリシーの例、リソースベースのポリシー
- [送信](sending.md): エラーの種類別の扱いと再試行、再送信、プロジェクト別の送信元
- [受信](receiving.md): アドレス、取り込み、なりすましとスパム
- [管理画面](admin.md): メール送信、メール受信、プロジェクトのメール設定

<a id="features"></a>

## 機能

| 機能 | 内容 | 有効にする条件 | 資料 |
| --- | --- | --- | --- |
| メール送信の再試行 | ジョブを動かすプロセスでの `raise_delivery_errors`、SES のエラーの種類に応じた再試行 (一時的なエラーは再試行し、アカウントの問題は再送信のために残し、メッセージの問題は捨てる) | Lambda では `REDMINE_ROLE=worker`。Lambda 以外のときは、ジョブを動かすプロセス | [sending.md](sending.md) |
| メール受信 | SES が S3 に置いたメールの取り込み (rake タスク `redmine_aws_ses:receive_mail`。中では Redmine 標準の `MailHandler` を使う)、SES のイベントの判定の確認 (スパムと DMARC は設定で選べ、ウイルスはいつも捨てる)、取り込みの記録 | 受信設定がある | [receiving.md](receiving.md#importing) |
| プロジェクト別のアドレス | プロジェクト別の受信アドレスと送信元、デフォルトアドレス、プロジェクトの設定の「メール」のタブ | プラグインの設定で有効にする。無効なら Redmine の標準と同じ (送信元は 1 つで、プロジェクトはサブアドレス `noreply+識別子@…` で選ぶ) | [receiving.md](receiving.md#addresses-per-project) |
| 管理画面 | [Redmine AWS](https://redmine-kit.github.io/redmine_aws/ja/admin.html#the-aws-menu) の「AWS」メニューの「メール送信」(SES アカウント) と「メール受信」(受信履歴) のタブ、プロジェクトの設定の中のプロジェクトのメール設定 | システム管理者。使っていない機能の画面は出さない | [admin.md](admin.md) |

<a id="outside-lambda"></a>

## Lambda 以外での利用

SES での送信 (`aws-actionmailer-ses`) と受信は、SES と S3 に届く Redmine なら動きます。受信のタスクは、受信したメールのメッセージ ID を渡して動かします。

AWS Lambda では、[Serverless](https://redmine-kit.github.io/serverless/ja/) が [Redmine AWS SQS](https://redmine-kit.github.io/redmine_aws_sqs/ja/) といっしょにインストールします。メールを送るジョブを動かし、最終的に失敗したものを記録して再送信できるようにするのは、Redmine AWS SQS です。

<a id="gems-and-code-layout"></a>

## gem とコード構成

gem は `redmine_aws`、`aws-actionmailer-ses`、`aws-sdk-sesv2`、`aws-sdk-s3` に依存します。チェックアウトで使うときは、プラグインの `Gemfile` が AWS の gem を追加し、Redmine AWS は `plugins/redmine_aws` に別にチェックアウトします。

`boot/redmine_aws_ses.rb` は、`aws-actionmailer-ses` (配信方法 `:ses_v2`) を読み込み、プロジェクトごとの送信元のためのインターセプターを登録します。プラグインは gem でもあるので、Bundler がこのファイルを Rails の初期化より前に読み込みます ([setup.md](setup.md#installation))。ほかは Redmine が読み込む `lib/redmine_aws/ses.rb` と `lib/redmine_aws/ses/` (Redmine AWS の名前空間の中のモジュール `RedmineAws::SES`)、`app/`、`db/` にあり、`init.rb` が有効にします。「AWS」の管理メニュー、そのタブ、接続テストは、このプラグインが必要とする [Redmine AWS](https://redmine-kit.github.io/redmine_aws/ja/) のものです。

<a id="tests"></a>

## テスト

Redmine 標準のしくみでテストを書き、Docker の中で動かします ([setup.md](setup.md#tests))。メールの取り込みのテストには、SES が追加するヘッダーを付けたメールを使います ([testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#email-redmine_aws_ses))。

<a id="database-tables"></a>

## データベーステーブル

受信したメールの記録 (`aws_ses_received_mails`)、プロジェクトのメール設定 (`aws_ses_project_mail_settings`)、メールのタブが表示する SES の状態 (`aws_ses_snapshots`) の 3 つのテーブルを追加します ([admin.md](admin.md))。

<a id="sponsors"></a>

## スポンサー

<Sponsors><a href="https://www.keyselect.co.jp/">KEY SELECT</a> <a href="https://localstack.cloud">LocalStack</a></Sponsors>

<a id="license"></a>

## ライセンス

Redmine AWS SES は、GNU General Public License バージョン 2 またはそれ以降のバージョンで公開しています。[LICENSE](../../LICENSE) を参照してください。Redmine の非公式のプラグインです。
