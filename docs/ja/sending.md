# 送信

Redmine Serverless SES が、Redmine のメールを Amazon SES で送るしくみと、送信に失敗したときの扱いです。送信には Rails の標準のしくみを使います。AWS の gem `aws-actionmailer-ses` の ActionMailer の配送の方法 `:ses_v2` が、SES v2 の `SendEmail` に、メッセージの全体(`content.raw`)と、宛先(To、Cc、Bcc)を別に渡します。Bcc の宛先は、メッセージには出ません。どの関数が送るかと SES のリソースは、[Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#sending) にあります。

2026-11-09 に、Redmine 7.0.3 と `aws-actionmailer-ses` 1.2.0 のソースで確認しました。

<a id="raising-errors"></a>

## エラーを出す

Redmine の本番の設定(`production.rb`)は `raise_delivery_errors = false` で、Redmine の `Mailer.deliver_mail` は、`ActionMailer::Base.raise_delivery_errors` が true でなければ、配送のエラーを握りつぶします。Redmine のメールのジョブ(`Mailer::DeliveryJob`。`ActionMailer::MailDeliveryJob` のサブクラス)は、例外が発生したときだけ失敗します。エラーが握りつぶされると、ジョブは成功し、キューはやり直しません。

そこで、プラグインは、ジョブを動かすプロセス(`REDMINE_ROLE=worker`)でだけ `raise_delivery_errors` を `true` にします。`init.rb` は `production.rb` のあとに動くので、この設定が残ります。ほかのプロセス(web の要求、期日のお知らせのような rake のタスク)は `false` のままにし、1 通の失敗でタスク全体が止まらないようにします。

<a id="handling-by-kind-of-error"></a>

## エラーの種類別の扱い

SES v2 の `SendEmail` のエラー(API リファレンスの一覧)を、3 つの種類に分けます。プラグインは、`Mailer::DeliveryJob` に SES のエラーのハンドラーを追加します(`rescue_from`。ActionMailer のものより後に宣言するので、先に試されます)。

| エラー | 意味 | 扱い |
| --- | --- | --- |
| `TooManyRequestsException`<br>`InternalFailure`<br>`ServiceUnavailable`<br>そのほかの 5xx<br>ネットワークのエラー | 一時的 | ジョブの中でやり直す。3、18、83、258 秒のあとに、5 回まで動かす |
| `MessageRejected`<br>`BadRequestException` | そのメッセージの中身や宛先の問題 | ジョブを捨てる。[Redmine Serverless SQS](https://redmine-kit.github.io/redmine_serverless_sqs/ja/) があれば、失敗の記録を残す |
| そのほか。たとえば<br>`SendingPausedException`<br>`AccountSuspendedException`<br>`MailFromDomainNotVerifiedException`<br>`NotFoundException`<br>`LimitExceededException`<br>`AccessDeniedException` | アカウントか設定の問題。直すまで、何度でも失敗する | ジョブの中ではやり直さずに例外を発生させる。キューがメッセージを受け取り直し、最後の受け取りのあとにデッドレターキューへ移し、そこで Redmine Serverless SQS が記録する |

- **待ち時間:** ActiveJob の `:polynomially_longer` から揺らぎを除いたものです(`実行回数⁴ + 2` 秒)。SQS で遅らせられる最長(15 分)に収まります。5 回目のあとは例外を発生させ、アカウントのエラーと同じく、キューのやり直しとデッドレターキューになります。
- **SDK のやり直し:** AWS の SDK も、ジョブより前に、429 と 5xx を自分でやり直します(既定のやり直しの設定)。
- **2 通届くことがある:** SES が受け付けたあとで応答が失われると、やり直しで同じメッセージを 2 回送ることがあります。

<a id="sending-again"></a>

## 送り直し

1. **通知を受ける:** デッドレターキューか失敗の記録のアラームで、メールの失敗を知ります(Serverless では CloudWatch のアラーム)。
2. **原因を直す:** 管理画面の「メール送信」のタブで、SES アカウント、ドメイン、サプレッションリストを確認します([admin.md](admin.md#sending-email))。
3. **送り直す:** 「失敗したジョブ」のリンクから Redmine Serverless SQS の「ジョブ」の画面を開き、失敗したメールを選んで送り直すか、デッドレターキューを戻します([その admin.md](https://redmine-kit.github.io/redmine_serverless_sqs/ja/admin.html#jobs))。

- **SES が受け付けたあとの失敗:** SES が受け付けたあとで、相手のメールサーバーが拒んだメール(バウンス)は、API のエラーではありません。SES はアドレスをサプレッションリストに入れ、そこへは送らなくなります。「メール送信」のタブでリストを見られます。

<a id="senders-per-project"></a>

## プロジェクト別の送信元

Redmine は、すべての通知を送信元のアドレス(`Setting.mail_from`)から送ります。プロジェクトごとのアドレスと、プロジェクトごとの送信元を有効にすると([receiving.md](receiving.md#addresses-per-project))、プラグインは、プロジェクトの通知を、そのプロジェクトのアドレスから送ります。

- **見分け方:** Redmine は、プロジェクトの通知(チケット、ニュース、文書、ファイル、フォーラム、wiki)に、`X-Redmine-Project` のヘッダーでプロジェクトの識別子を付けます(`Mailer#redmine_headers`)。ActionMailer のインターセプター(送る前にメールを書き換える Rails の標準のしくみ。`boot/` が登録する)がこれを読み、送信元を `<識別子>@<ドメイン>` に替えます。
- **表示名:** Redmine の表示名(送信元のアドレスに表示名がなければ、作成者の名前)はそのまま使います。
- **ヘッダーのないメール:** プロジェクトに属さないメールは、送信元のアドレス(デフォルトアドレス)のままです([receiving.md](receiving.md#address-for-the-whole-redmine))。
- **メールを受け取らないプロジェクト:** 送信元はプロジェクトのアドレスですが、返信は取り込まれないので、`Reply-To` を送信元のアドレスにします。
- **選べる:** 既定は無効です。「メール受信」のタブの「受信設定」の「プロジェクトのアドレスから通知を送信」で有効にします。

<a id="tests"></a>

## テスト

| 対象 | 確認すること |
| --- | --- |
| SES での送信 | 通知が `aws-actionmailer-ses` を通って SES v2(LocalStack。トークンがなければ moto)に送られる。確認済みの ID でない送信元は、worker で `MessageRejected` の例外を発生させる(モックした応答。下記) |
| 接続テスト | SES v2 の `GetAccount`(モックした応答。下記) |
| エラーの種類別 | SDK の応答のスタブで `SendEmail` のエラーを 1 つずつ起こす。一時的なエラーはジョブの中でやり直し、最後の実行のあとは例外を発生させる。メッセージのエラーは捨てる。アカウントのエラーはキューのために例外を発生させる |
| worker だけ | `raise_delivery_errors` は `REDMINE_ROLE=worker` のときだけ設定する |
| プロジェクト別の送信元 | インターセプターは、設定が有効なときだけ、送信元と `Reply-To` を替える |
