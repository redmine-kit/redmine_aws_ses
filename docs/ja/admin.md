# 管理画面

Redmine Serverless SES の管理画面です。Redmine の管理者だけが開けます(`require_admin`)。プロジェクトのメールの設定だけは、プラグインが足すプロジェクトの権限を持つ人も変えられます(下記)。画面は、[Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/ja/admin.html#the-serverless-menu) をインストールしているかどうかにかかわらず、すべての Redmine Serverless のプラグインが共有する Redmine の管理のメニューの「Serverless」の下の、「メールの送信」と「メールの受信」のタブになります。プロジェクトのメールの設定は、代わりにプロジェクトの設定のタブになります。

この資料の仕様は、2026-11-08 時点の公式の情報と、Redmine 7.0.3 のソースで確認したものです。出典は [sources.md](https://redmine-kit.github.io/serverless/ja/sources.html) にあります。

| 項目 | 内容 |
| --- | --- |
| 秘密の値は出さない | AWS の認証情報と、受信したメールの本文は画面に出しません。SES の状態と MX のレコードは 1 分だけキャッシュします |
| 設定は画面で変える | 受信のオプションは、プラグインの設定(Redmine の `Setting.plugin_redmine_serverless_ses`、データベースに入る)にし、「メールの受信」のタブで変えます。プラグインの一覧に「設定」のリンクは出ません |
| 操作を記録する | サプレッションリストからの削除、もう一度の取得、設定の変更は、誰が何をしたかを Redmine のログに書きます(`[redmine_serverless_ses] <ログイン> ...`) |
| 接続の確認 | Redmine Serverless を入れているときは、その接続の確認で、SES v2 の `GetAccount` も呼びます |

<a id="sending-email"></a>

## メールの送信

![「メールの送信」のタブ。SES のアカウント、送信元のドメイン、サプレッションリスト](./images/mail-sending.png)

| 項目 | 中身 | 取得元 |
| --- | --- | --- |
| アカウントの状態 | 本番での利用(サンドボックスの解除)、送信が有効か、制限の状態 | SES v2 の `GetAccount` |
| 送信の上限 | 24 時間の上限、1 秒あたりの上限、直近 24 時間に送った数 | 同上 |
| 送信元のドメイン | 管理画面の送信元のアドレスのドメインが確認済みか、DKIM の状態 | SES v2 の `GetEmailIdentity` |
| サプレッションリスト | SES が送信を止めているアドレス(バウンスと苦情で登録されたもの)と、そのアドレスを持つ Redmine のユーザー。最初の 100 件 | SES v2 の `ListSuppressedDestinations` |
| サプレッションリストからの削除 | アドレスごとのボタン。確認のあとで消す | SES v2 の `DeleteSuppressedDestination` |
| テストのメール | Redmine の標準の「テストメールを送信」(管理 › 設定 の「メール通知」)へのリンク。同じ機能は足さない | — |
| 失敗したメール | Redmine Serverless SQS を入れているときは、その「ジョブ」の画面の、失敗したメールだけの一覧へのリンク | — |

| 項目 | 内容 |
| --- | --- |
| サプレッションリストを出す理由 | 一度バウンスしたアドレスには、SES が送らなくなります。Redmine からは送ったように見えるので、「通知が届かない」と言われたときに、この画面で確認できます |
| テストのメール | Redmine の標準のテストのメールは、画面の要求の中で送る(`deliver_now`)ので、`redmine-web` にも SES で送る権限を与えます([mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#ses)) |

<a id="receiving-email"></a>

## メールの受信

![「メールの受信」のタブ。アドレスと MX レコード、取得した 1 通と捨てた 2 通の受信の記録、受信の設定](./images/mail-receiving.png)

| 項目 | 中身 | 取得元 |
| --- | --- | --- |
| アドレス | Redmine のドメイン(送信元のアドレスのドメイン)、Redmine 全体のアドレス、プロジェクトのアドレス(受け取るか) | プラグインの設定と、プロジェクトのメールの設定 |
| MX のレコード | Redmine のドメインの MX のホスト。SES の受信のエンドポイントになっているかを確認する | DNS の問い合わせ。タイムアウトは 2 秒 |
| 受け取ったメール | 受信の日時、送信者、件名、プロジェクト、SES の判定(ウイルス、迷惑メール、DMARC)、結果(チケット、または取得しなかった理由)。新しい 100 件。「取得しなかったものだけ」で絞り込める | プラグインの表(下記) |
| もう一度取得する | 選んだメールをもう一度取得する | メールごとのジョブ(`ServerlessReimportMailJob`。Serverless では SQS に入り、`redmine-worker` が取り込む) |
| 受信の設定 | Redmine 全体のアドレス(`@` の前)、そこに届いたメール(取得しない、または既定のプロジェクトに入れる)、既定のプロジェクト、「取得するメール」(DMARC が通らないメールも取得するか、迷惑メールと判定されたメールも取得するか。どちらも既定はオフで、画面に説明を出す。ウイルスはいつも捨てる)、「プロジェクト」(プロジェクト別のアドレスを使うか、プロジェクトの通知をプロジェクトのアドレスから送るか) | プラグインの設定(画面で変える)。DMARC に失敗したメールは、設定にかかわらず取り込まない([receiving.md](receiving.md#spoofing-and-spam)) |

| 項目 | 内容 |
| --- | --- |
| 取得の記録 | `redmine_serverless_ses:receive_mail` は、メールごとの結果を、プラグインの表(`serverless_received_mails`)に入れます。送信者、件名、SES のイベントのエンベロープの宛先と判定、プロジェクト、作ったチケットや足した注記です。本文は入れず、メールのバケットのキー(`inbound/` か `processed/`)を入れます。取り込み直しは、同じ記録を書き換えます。90 日より古い記録は、`rake redmine_serverless_ses:prune_records` が消します。Serverless は毎日動かします([security.md](https://redmine-kit.github.io/serverless/ja/security.html#retention-periods)) |
| 取得しない理由 | SES の判定がない(イベントを通して受け取っていないメール)、ウイルス、スパム、DMARC の失敗、自動の返信、受け取るプロジェクトがない、Redmine が取得できなかった(たとえば、登録していない送信者や、権限のない送信者。理由は Redmine のログにある)のどれかです。取り込まなかったメールは `inbound/` に残り、原因を直してから取り込み直せます |
| もう一度取得する | 画面は `redmine-task` を直接は呼ばず、キューにジョブを入れます。こうすると、`redmine-web` に、メールのバケットを読む権限も、Lambda を呼ぶ権限も要りません。Redmine Serverless SQS を入れていれば、このジョブのクラスを、実行してよいジョブのクラスに足します |
| 受信の設定を画面に置く理由 | 既定のプロジェクトを変えるたびにデプロイしなくて済みます。`redmine_serverless_ses:receive_mail` は、動くたびにデータベースから設定を読みます |

<a id="project-email-settings"></a>

## プロジェクトのメールの設定

プロジェクトごとのアドレスを使うとき、プロジェクトの設定に「メール」のタブを足します。プロジェクトごとのアドレスを設定します([receiving.md](receiving.md#addresses-per-project))。設定は、プラグインの表(`serverless_project_mail_settings`)に入ります。Redmine の設定(`Setting`。名前と値)は Redmine 全体のものだけで、プロジェクトごとの設定の表がないためです。プロジェクトを削除すると、その行も消えます。

![プロジェクトの設定の「メール」のタブ](./images/project-mail.png)

| 項目 | 中身 |
| --- | --- |
| アドレス | `<識別子か別名>@<Redmine のドメイン>`。表示だけ。識別子が 64 文字より長いプロジェクトには、別名が要る |
| メールを受け取るか | 受け取らない(既定)か、受け取る |
| 別名 | 識別子とは別のアドレス(`@` の前。英小文字、数字、`.`、`_`、`-`)。ほかのプロジェクトの識別子や別名、Redmine 全体のアドレス、予約した名前(`postmaster`、`abuse`、`hostmaster`、`webmaster`、`mailer-daemon`、`root`、`admin`、`administrator`、`noreply`、`no-reply`、`security`)と同じなら、保存できない |
| 既定の値 | 作るチケットのトラッカー、カテゴリー、優先度、担当者、プライベートにするか |
| 登録していないアドレスの扱い | 取得しない(既定)、匿名ユーザーとして受け付ける、アカウントを作る(Redmine の `unknown_user` の `ignore`、`accept`、`create`) |

| 項目 | 内容 |
| --- | --- |
| 変えられる人 | Redmine の管理者と、プラグインが足すプロジェクトの権限「メールの設定の管理」を持つメンバーです |
| 登録していないアドレスを受け付けるとき | 問い合わせの窓口のように、外の人からのメールを受けるときに使います。迷惑メールが増えるので、DMARC の確認は外しません([receiving.md](receiving.md#spoofing-and-spam)) |

<a id="permissions"></a>

## 権限

これらの画面のために、Redmine の web の要求を動かすロールに、SES の状態を読む権限と、サプレッションリストからアドレスを外す権限を与えます。一覧と例のポリシーは [iam.md](iam.md) にあります。

<a id="tests"></a>

## テスト

画面ごとに、Redmine の機能のテストがあります。SES には SDK の応答のスタブを使います([testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#administration-pages))。

このページの画面のスクリーンショットは、`bin/screenshots` で撮ります(Docker の中のヘッドレスの Chromium と、Redmine のテストのデータと、例の SES の応答と受信したメール)。画面を変えたら実行します。
