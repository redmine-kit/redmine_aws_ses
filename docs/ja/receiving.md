# 受信

Redmine Serverless SES が、SES の受け取ったメールを取り込むしくみです。アドレス、プロジェクトの決め方、なりすましと迷惑メールの確認、Redmine の `MailHandler` に渡すオプションを書きます。SES は、メッセージをメールのバケット(`inbound/<メッセージ ID>`)に置き、取り込みを起動します。ドメイン、受信のルール、バケットは [Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#receiving) にあります。

2026-11-09 に、Redmine 7.0.3 のソースで確認しました。

<a id="addresses-per-project"></a>

## プロジェクト別のアドレス

| アドレス | 使い方 |
| --- | --- |
| `<プロジェクトの識別子>@<ドメイン>` | プロジェクトのアドレス。ここに届いたメールは、そのプロジェクトのチケットになる。プロジェクトの通知を、ここから送ることもできる([sending.md](sending.md#senders-per-project)) |
| プロジェクトの別名(例: `support@<ドメイン>`) | 識別子とは別の、覚えやすいアドレス。プロジェクトの設定で決める |
| `redmine@<ドメイン>`(Redmine 全体のアドレス) | プロジェクトに属さないメールの送信元(下の「Redmine 全体のアドレス」) |

`<ドメイン>` は Redmine のドメインで、送信元のアドレス(`Setting.mail_from`)のドメインです。

- **識別子とアドレス:** Redmine のプロジェクトの識別子は、英小文字、数字、`-`、`_` でできているので、そのまま `@` の前に使えます。`@` の前は 64 文字までなので、識別子がそれより長いプロジェクトには別名が要ります。
- **受け取るか:** プロジェクトごとに、メールを受け取るかを選びます(既定は受け取らない)。受け取らないプロジェクトへのメールは、取り込まずに記録します。
- **別名:** ほかのプロジェクトの識別子や別名、Redmine 全体のアドレス、予約した名前とは重ねられません([admin.md](admin.md#project-email-settings))。
- **プロジェクトの設定:** プロジェクトの設定の「メール」のタブで、受け取るか、別名、既定の値を決めます([admin.md](admin.md#project-email-settings))。設定は、プラグインの表(`serverless_project_mail_settings`)に入ります。

<a id="without-addresses-per-project"></a>

## プロジェクト別のアドレスを使わないとき

プロジェクトごとのアドレスが無効(既定)なら、Redmine の標準と同じに受け取ります。

- **受け取るアドレス:** Redmine 全体のアドレスだけです。
- **プロジェクトの決め方:** Redmine のサブアドレス(`redmine+<識別子>@<ドメイン>`)です。プラグインは、サブアドレスを `To` と `Cc` のヘッダーではなく、エンベロープの宛先から読むので、Bcc でも決まります。サブアドレスのないメールは、「メールの受信」のタブの設定のとおり、既定のプロジェクトに入れるか、取り込みません。
- **送信元:** すべての通知を、Redmine 全体のアドレスから送ります。

<a id="address-for-the-whole-redmine"></a>

## Redmine 全体のアドレス

プロジェクトに属さないメールは、送信元のアドレス(`Setting.mail_from`)、つまり Redmine 全体のアドレスから送ります。

| Redmine 全体のアドレスから送るメール | Redmine のメーラーのメソッド |
| --- | --- |
| パスワードの再設定 | `lost_password` |
| アカウントの登録の確認、有効化の依頼、有効化の通知 | `register`<br>`account_activation_request`<br>`account_activated` |
| アカウントの情報(管理者が作ったアカウント) | `account_information` |
| 期日のリマインダー(複数のプロジェクトのチケットをまとめる) | `reminder` |
| セキュリティの通知、設定の変更の通知 | `security_notification`<br>`settings_updated` |
| テストのメール | `test_email` |

上のメソッドは、Redmine 7.0.3 のメーラーのうち、プロジェクトのヘッダー(`X-Redmine-Project`)を付けないものです(`app/models/mailer.rb`)。

- **`@` の前:** 「メールの受信」のタブで決めます(既定は `redmine`。`noreply` なども使えます)。プロジェクトの別名にはできません。
- **そこに届いたメール:** 既定のプロジェクトに入れるか、取り込みません(既定)。パスワードの再設定などへの返信は、ふつう取り込む必要はありません。

<a id="importing"></a>

## 取り込み

rake のタスク `redmine_serverless_ses:receive_mail` が、メッセージを 1 通取り込みます。

1. SES のイベントの判定を確認します(下の「なりすましと迷惑メール」)。
2. イベントの宛先から、プロジェクトを決めます(下記)。
3. メールのバケットから全文を取ります(`inbound/`。取り込み直しなら `processed/`)。
4. Redmine の `MailHandler.safe_receive` に、全文とオプションを渡します。Redmine の `rake redmine:email:read` と同じ処理です。
5. 成功したら、メッセージを `processed/` に移します(`CopyObject` のあと `DeleteObject`)。実行ごとに記録を残します([admin.md](admin.md#receiving-email))。

タスクは、SES のイベントの値を、変数で受け取ります。

| 変数 | SES のイベントの値 |
| --- | --- |
| `MESSAGE_ID` | `mail.messageId`(メールのバケットのキー) |
| `SES_RECIPIENTS` | `receipt.recipients`(エンベロープの宛先。カンマ区切り) |
| `SES_SPAM_VERDICT`<br>`SES_VIRUS_VERDICT`<br>`SES_DMARC_VERDICT`<br>`SES_SPF_VERDICT`<br>`SES_DKIM_VERDICT` | `receipt.spamVerdict.status` など |
| `SES_DMARC_POLICY` | `receipt.dmarcPolicy` |

Lambda では、SES の受信のルールがタスクの関数を呼び、そのハンドラーがこれらを設定します([Serverless の tasks.md](https://redmine-kit.github.io/serverless/ja/tasks.html#kinds-of-events))。取り込み直しは `MESSAGE_ID` だけを渡し、最初の実行で記録したものを使います。

**プロジェクトの決め方:**

- **宛先は SES のイベントから取る:** `To` と `Cc` のヘッダーではなく、エンベロープの宛先(SMTP の `RCPT TO`)を使うので、Bcc で届いたメールも決まります。取り込み直しのために、取り込みの記録に残します。
- **当てはめ方:** 宛先のうち Redmine のドメインのアドレスを順に見て、メールを受け取るプロジェクトの識別子か別名に当てはまる最初のものにします。当てはまるものがなければ、取り込まずに記録します。
- **Redmine に渡す:** プロジェクトの識別子と既定の値を、`MailHandler` のオプション(`issue[:project]` など)で渡します。Redmine の決め方では本文の `Project:` のキーワードが勝つので、`allow_override` を空にし、キーワードでプロジェクトを変えられないようにします。
- **返信:** Redmine は、通知のメールへの返信を、`In-Reply-To` と `References` のヘッダーから、元のチケットの注記にします(`MailHandler#dispatch`)。返信をどのアドレスに送っても、元のチケットに付きます。

| オプション | 値 | 意味 |
| --- | --- | --- |
| `unknown_user` | プロジェクトの設定(既定は `ignore`) | Redmine に登録していないアドレスからのメールの扱い |
| `no_permission_check` | `0` | 送信者の権限を確認する |
| `allow_override` | 空 | 本文のキーワードで属性を変えない |
| `issue[:project]` | 宛先から決めたプロジェクト | 上記 |
| `issue[:tracker]` などの既定の値 | プロジェクトの既定の値(名前で渡す) | 作るチケットの値 |

- **自動の返信:** `Auto-Submitted`(`auto-replied`、`auto-generated`)か `X-Autoreply: yes` のあるメール(`MailHandler.ignored_emails_headers`)は、取り込まずに、自動の返信として記録します。通知と取り込みが繰り返されないようにするためです。
- **Redmine が取り込まないとき:** `MailHandler` が受け付けないメール(たとえば、`ignore` での登録のない送信者や、権限のない送信者)は、取り込まなかったものとして記録し、`inbound/` に残します。理由は Redmine のログにあります。
- **添付ファイル:** 添付ファイルは Redmine の添付ファイルとして保存します([Redmine Serverless S3](https://redmine-kit.github.io/redmine_serverless_s3/ja/) があれば S3 に置きます)。

<a id="spoofing-and-spam"></a>

## なりすましと迷惑メール

Redmine は、メールの差出人(`From`)のアドレスで、どのユーザーからのメールかを決めます。差出人を偽ったメールを取り込むと、そのユーザーとしてチケットが作られます。そこで、取り込みは、SES のイベントの判定を確認します。

| イベントの判定(`receipt`) | `PASS` でないとき | 設定 |
| --- | --- | --- |
| `virusVerdict.status` | いつも取り込まない。添付ファイルが全員に配られるため | — |
| `spamVerdict.status` | 取得しない | 「迷惑メールと判定されたメールも取得する」(`import_spam`。既定はオフ) |
| `dmarcVerdict.status` | 取得しない | 「DMARC が通らないメールも取得する」(`import_without_dmarc_pass`。既定はオフ) |

値は `PASS`、`FAIL`、`GRAY`、`PROCESSING_FAILED` のどれかです。判定がないときは、`PASS` でないものとして扱います。`spfVerdict`、`dkimVerdict`、`dmarcPolicy` も記録しますが、これだけでは決めません。判定は、取り込んだかどうかにかかわらず記録します。

- **既定で DMARC を求める理由:** DMARC が通っていれば、差出人のドメインが SPF か DKIM で確認されています。Microsoft 365 や Gmail から送ったメールは、ふつうは通ります。設定をオンにすると、誰でも、登録した利用者の名前でメールを送れてしまいます。
- **SES のイベントから取り、ヘッダーからは取らない:** 判定と宛先はイベントから取り、メッセージのヘッダー(`X-SES-*`、`Authentication-Results`)からは取りません。送信者が同じ名前のヘッダーを付けられるからです。
- **判定がないとき:** 判定のないメッセージ(イベントからも、前の記録からも得られないもの)は取り込みません(`no_verdict`)。
- **取り込み直し:** 取り込みの記録が判定と宛先を持ち、取り込み直しはそれを使います。設定は、そのときのものを使います。

<a id="settings-for-receiving-replies"></a>

## 返信を受けるための設定

| 設定 | 値 | 理由 |
| --- | --- | --- |
| Redmine の管理画面の「送信元メールアドレス」 | Redmine 全体のアドレス(例: `redmine@redmine.example.com`) | プラグインは、ここから Redmine のドメインも知る |
| 「この行以降を切り捨てる」 | 引用の前の行(「--- この行より上に返信を書いてください ---」など) | 返信の引用を注記に入れない |

<a id="tests"></a>

## テスト

| 対象 | 確認すること |
| --- | --- |
| 判定 | 設定のすべての組み合わせ。ウイルスはいつも取り込まない。判定がないとき |
| 取り込み | S3 のメールのバケット(LocalStack か moto)で、SES のイベントの値(`test/fixtures/ses_event.json`)といっしょに取り込む。宛先のプロジェクト、Bcc、プロジェクトを変えられない `Project:` のキーワード、取り込まないそれぞれの理由、何も変えない偽の SES のヘッダー、`processed/` への移動、記録からの取り込み直し、rake のタスク |
| プロジェクトの決め方 | プロジェクトごとのアドレスと別名、受け取らないプロジェクト、Redmine 全体のアドレス、サブアドレス |
| プロジェクトの設定 | 使っている別名と予約した名前を拒む。権限のある人だけが変えられる |
