# 管理画面

Redmine Serverless SES の管理画面の設計です。Redmine の管理者だけが開けます(`require_admin`)。プロジェクトのメールの設定だけは、プラグインが足すプロジェクトの権限を持つ人も開けます(下記)。画面は、[Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/ja/admin.html#the-serverless-menu) をインストールしているかどうかにかかわらず、すべての Redmine Serverless のプラグインが共有する Redmine の管理のメニューの「Serverless」の下の、「メールの送信」と「メールの受信」のタブになります。プロジェクトのメールの設定は、代わりにプロジェクトの設定のタブになります。

この資料の仕様は、2026-11-08 時点の公式の情報と、Redmine 7.0.3 のソースで確認したものです。出典は [sources.md](https://redmine-kit.github.io/serverless/ja/sources.html) にあります。

- **秘密の値は出さない:** AWS の認証情報は画面に出しません。SES の状態は 1 分だけキャッシュし、重い確認はボタンを押したときに行います。
- **設定は画面で変える:** 受信のオプションは、プラグインの設定(Redmine の `Setting.plugin_*`、データベースに入る)にし、画面で変えます。
- **接続の確認:** Redmine Serverless を入れているときは、その接続の確認で、SES v2 の `GetAccount` も呼びます。

<a id="sending-email"></a>

## メールの送信

| 項目 | 中身 | 取り方 |
| --- | --- | --- |
| アカウントの状態 | 本番での利用(サンドボックスの解除)、送信が有効か、制限の状態 | SES v2 の `GetAccount` |
| 送信の上限 | 24 時間の上限、1 秒あたりの上限、直近 24 時間に送った数 | 同上 |
| 送信元のドメイン | 管理画面の送信元のアドレスのドメインが確認済みか、DKIM の状態 | SES v2 の `GetEmailIdentity` |
| サプレッションリスト | SES が送信を止めているアドレス(バウンスと苦情で登録されたもの)の一覧。Redmine のユーザーのアドレスと突き合わせて表示する | SES v2 の `ListSuppressedDestinations` |
| サプレッションリストからの削除 | ボタンで、アドレスを一覧から外す | SES v2 の `DeleteSuppressedDestination` |
| テストのメール | Redmine の標準の「テストメールを送信」(管理の「設定」の「メール通知」)へのリンク。同じ機能は足さない | — |
| 失敗したメール | Redmine Serverless SQS を入れているときは、その「ジョブ」の画面の、失敗したメールだけの一覧へのリンク | — |

- **サプレッションリストを出す理由:** あるアドレスが一度バウンスすると、SES はそのアドレスへの送信を止めます。Redmine からは送れたように見えるので、「通知が届かない」と言われたときに、ここで確認できるようにします。
- **テストのメール:** Redmine の標準のテストのメールは、画面の要求の中で送る(`deliver_now`)ので、`redmine-web` にも SES の送信の権限を付けます([mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#ses))。

<a id="receiving-email"></a>

## メールの受信

| 項目 | 中身 | 取り方 |
| --- | --- | --- |
| 受信のアドレス | Redmine のサブドメイン、全体用のアドレス、プロジェクトごとのアドレスの一覧(受けるかどうか、別名) | プラグインの設定と、プロジェクトのメールの設定 |
| MX のレコード | 受信のホスト名の MX が、SES の受信の宛先を向いているか | DNS を引く(Lambda の既定の DNS で、インターネットの名前を引く) |
| 受け取ったメール | 受け取った時刻、差出人、件名、結果(作ったチケット、付けた注記、捨てた理由) | プラグインのテーブル(下記) |
| 取り込み直し | 捨てたメールや失敗したメールを、もう一度取り込む | 取り込みのジョブをジョブのキューに積む(Serverless では SQS に積み、`redmine-worker` が取り込む) |
| 受信の設定 | 全体用のアドレス(`@` の前)、全体用のアドレスに届いたメールの扱い(既定のプロジェクトに入れるか、捨てるか)、プロジェクトごとの送信元を使うか | プラグインの設定(画面で変える)。DMARC が通らないメールは、設定によらず捨てる([mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#spoofing-and-spam)) |

- **取り込みの記録:** `redmine_serverless_ses:receive_mail` が、メールごとの結果(宛先と、当てはめたプロジェクトを含む)を、プラグインのテーブル(`serverless_received_mails`)に残します。メールの本文は残さず、S3 の場所(`inbound/` か `processed/` のキー)を残します。記録は 90 日で消します([security.md](https://redmine-kit.github.io/serverless/ja/security.html#retention-periods))。
- **捨てた理由:** ウイルス、迷惑メール、DMARC が通らない、登録のないアドレス、自動応答、Redmine の取り込みのエラーのどれかを出します。差出人を偽ったメールが来ていないかを、ここで確認できます。
- **取り込み直し:** 画面から `redmine-task` を直接呼ばず、ジョブを SQS に積みます。`redmine-web` に Lambda を呼ぶ権限を持たせずに済みます。
- **受信の設定を画面にする理由:** 既定のプロジェクトを変えるたびにデプロイしなくて済みます。`redmine_serverless_ses:receive_mail` は、実行のたびにデータベースから設定を読みます。

<a id="project-email-settings"></a>

## プロジェクトのメールの設定

プロジェクトの設定に「メール」のタブを足します。プロジェクトごとのアドレス([mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#addresses-per-project))を設定します。

| 項目 | 中身 |
| --- | --- |
| アドレス | `<識別子>@<Redmine のサブドメイン>`。表示だけ |
| メールを受けるか | 受けない(既定)か、受ける |
| 別名 | 識別子とは別のアドレス(`@` の前)。ほかのプロジェクトの識別子、別名、予約した名前と重なると保存できない |
| 既定の値 | 作るチケットのトラッカー、カテゴリー、優先度、担当者、プライベートにするか |
| 登録のないアドレスの扱い | 取り込まない(既定)、匿名のユーザーで受ける、アカウントを作る(Redmine の `unknown_user` の `ignore`、`accept`、`create`) |

- **開ける人:** Redmine の管理者と、プラグインが足すプロジェクトの権限「メールの設定の管理」を持つ人です。
- **登録のないアドレスを受けるとき:** 問い合わせの窓口のように、外の人からのメールを受けるときに使います。迷惑メールが増えるので、DMARC の確認([mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#spoofing-and-spam))を外さないようにします。

<a id="permissions"></a>

## 権限

画面のために、Redmine の Web の要求を動かすロールに、SES の状態を読む権限と、サプレッションリストからアドレスを外す権限を足します。一覧とポリシーの例は [iam.md](iam.md) にあります。

<a id="tests"></a>

## テスト

画面ごとに、Redmine の機能のテストとシステムのテストを書きます([testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#administration-pages))。
