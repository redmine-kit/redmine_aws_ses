# Redmine Serverless SES

Redmine Serverless SES(`redmine_serverless_ses`)は、Redmine のメールを Amazon SES で送受信するための Redmine のプラグインです。エラーの種類ごとの送信のやり直し、SES で受けたメールの取り込み、なりすましと迷惑メールの確認、プロジェクトごとのアドレスを持ちます。Redmine 本体のファイルは書き換えず、Redmine の標準の拡張の仕組みだけで作ります。今は設計段階で、資料だけがあります。

- [準備](setup.md): インストール、設定、SES と S3 のリソース、IAM の権限、ネットワーク
- [管理画面](admin.md): メールの送信、メールの受信、プロジェクトのメールの設定

<a id="features"></a>

## 機能

| 機能 | 中身 | 有効にする条件 | 設計 |
| --- | --- | --- | --- |
| メールの送信のやり直し | ジョブを動かすプロセスでの `raise_delivery_errors`、SES のエラーの種類ごとのやり直し(一時的なエラーはやり直し、アカウントの問題は送り直しのために残し、メッセージの問題は捨てる) | Lambda では `REDMINE_ROLE=worker`。Lambda 以外のときは、ジョブを動かすプロセス | [mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#when-sending-fails) |
| メールの受信 | SES が S3 に置いたメールの取り込み(rake のタスク `redmine_serverless_ses:receive_mail`。中では Redmine の標準の `MailHandler` を使う)、なりすましと迷惑メールの確認、取り込みの記録 | 受信の設定がある | [mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#importing) |
| プロジェクトごとのアドレス | プロジェクトごとの受信のアドレスと送信元、全体用のアドレス、プロジェクトの設定の「メール」のタブ | プラグインの設定で有効にする。無効なら Redmine の標準と同じ(送信元は 1 つで、プロジェクトはサブアドレス `redmine+識別子@…` で選ぶ) | [mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#addresses-per-project) |
| 管理画面 | メールの送信(SES の状態)、メールの受信、プロジェクトのメールの設定 | 管理者。使っていない機能の画面は出さない | [admin.md](admin.md) |

- **Lambda でも、Lambda 以外でも:** SES での送信(`aws-actionmailer-ses`)と受信は、SES と S3 に届く Redmine なら動きます。受信のタスクは、受けたメールのメッセージの ID を渡して動かします。AWS Lambda では、[Serverless](https://redmine-kit.github.io/serverless/ja/) が [Redmine Serverless SQS](https://redmine-kit.github.io/redmine_serverless_sqs/ja/) といっしょに入れます。メールを送るジョブを動かし、最後に失敗したものを記録して送り直せるようにするのは、Redmine Serverless SQS です。
- **gem:** プラグインが使う gem は、プラグインの `Gemfile` に書きます。Redmine の `Gemfile` は、`plugins/*/Gemfile` も読み込みます。
- **テスト:** Redmine の標準の仕組み(`rake redmine:plugins:test`)でテストを書きます。メールの取り込みのテストには、Redmine のテスト用のメールの見本に、SES が足すヘッダーを付けて使います([testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#email-redmine_serverless_ses))。
- **migration:** 受け取ったメールの記録(`serverless_received_mails`)と、プロジェクトのメールの設定(`serverless_project_mail_settings`)のテーブルを足します([admin.md](admin.md))。
