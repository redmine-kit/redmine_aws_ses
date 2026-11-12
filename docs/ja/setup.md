# 導入

Redmine AWS SES を使う Redmine に要るもの (インストール、設定、SES と S3 のリソース、IAM 権限、ネットワーク) です。AWS Lambda でも、ふつうのサーバーでも同じです。[Serverless](https://redmine-kit.github.io/serverless/ja/) は、これを CloudFormation でまとめて作ります。このページは、手で用意するときや、Serverless が作るものを確認するときのためのものです。

<a id="requirements"></a>

## 動作環境

- Redmine 7.0 以降。
- `plugins/redmine_aws` の [Redmine AWS](https://redmine-kit.github.io/redmine_aws/ja/) (`redmine_aws`) 0.1 以降。これがないと Redmine は起動しません (`init.rb` の `requires_redmine_plugin`)。gem もこれに依存します。「AWS」の管理メニューを追加します。
- AWS の認証情報で SES と S3 に届くプロセス (Lambda では実行ロール、ほかではインスタンスプロファイルやタスクロール)。Redmine にアクセスキーや SMTP のパスワードは置きません。
- 送信には、AWS の公式の gem `aws-actionmailer-ses` (配信方法は `:ses_v2`) ([Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#gems))。
- 送信の再試行には、別のプロセスで動くジョブ (Lambda では `REDMINE_ROLE=worker`。最終的に失敗したジョブは [Redmine AWS SQS](https://redmine-kit.github.io/redmine_aws_sqs/ja/) が記録します)。

<a id="installation"></a>

## インストール

1. プラグインを Redmine 7.0 の `plugins/redmine_aws_ses` に、Redmine AWS を `plugins/redmine_aws` に置きます。下の gem か、リポジトリのチェックアウトです。
2. プラグインを gem として `Gemfile.local` に追加し、インストールします。

   ```sh
   bundle install
   ```

   こうすると、Bundler が、Rails の初期化より前に `boot/redmine_aws_ses.rb` を読み込みます。配信方法 `:ses_v2` を登録する `aws-actionmailer-ses` と、プロジェクトごとの送信元のためのインターセプターを読み込みます。チェックアウトなら、両方をパスで追加します。Redmine AWS も書きます。プラグインの gemspec が必要とし、rubygems.org にはないためです。Bundler は読み込みません (読み込むのは Redmine です)。Redmine AWS のプラグインを複数追加するときも、`redmine_aws` は 1 回だけ書きます。Bundler は、同じ gem を 2 つのソースから取ることを拒み、重複には警告を出します。

   ```ruby
   # Redmine の Gemfile.local
   gem 'redmine_aws', path: 'plugins/redmine_aws', require: false
   gem 'redmine_aws_ses', path: 'plugins/redmine_aws_ses'
   ```

3. プラグインの migration を実行します。

   ```sh
   bin/rake redmine:plugins:migrate
   ```

   受け取ったメールの記録 (`aws_ses_received_mails`)、プロジェクトのメール設定 (`aws_ses_project_mail_settings`)、SES の状態 (`aws_ses_snapshots`) のテーブルを作ります。
4. `config/configuration.yml` に送信を設定します。

   ```yaml
   production:
     email_delivery:
       delivery_method: :ses_v2
       ses_v2_settings:
         region: <region>
   ```

<a id="gem"></a>

### gem

バージョンのタグ (`v*`) ごとに、プラグインを gem として GitHub Packages (`https://rubygems.pkg.github.com/redmine-kit`) に公開します (`.github/workflows/gem.yml`)。gem は、動かすためのファイル (`init.rb`、`boot/`、`lib/`、`app/`、`config/`、`db/`、`help/`、`LICENSE`) を持ち、`redmine_aws`、`aws-actionmailer-ses`、`aws-sdk-sesv2`、`aws-sdk-s3` に依存します。プラグインの `Gemfile` は入れません。Redmine AWS の gem は、Bundler が同じソースからいっしょにインストールするので、`Gemfile.local` にはプラグインだけを書きます。Redmine は `plugins/` のプラグインだけを読み込むので、インストールした gem をそこにリンクします。

```ruby
# Redmine の Gemfile.local
source 'https://rubygems.pkg.github.com/redmine-kit' do
  gem 'redmine_aws_ses'
end
```

```sh
bundle config set --global rubygems.pkg.github.com <ユーザー>:<トークン>   # か、変数 BUNDLE_RUBYGEMS__PKG__GITHUB__COM
bundle install
ln -s "$(bundle info --path redmine_aws)" plugins/redmine_aws
ln -s "$(bundle info --path redmine_aws_ses)" plugins/redmine_aws_ses
```

GitHub Packages からインストールするには、公開のパッケージでも、`read:packages` の権限を持つ GitHub のトークンが要ります。ほかのリポジトリのワークフローは、パッケージの設定 (「Manage Actions access」) でそのリポジトリに Read を与えると、自分の `GITHUB_TOKEN` (`packages: read`) で読めます。

<a id="configuration"></a>

## 設定

| キー | 説明 | パラメーター |
| --- | --- | --- |
| `REDMINE_MAIL_BUCKET` | SES が受け取ったメールを置くバケット (`inbound/<メッセージ ID>`。取り込んだメールは `processed/` に移す) | 受信するなら必須。取り込むプロセス (タスクと、再取得のための worker) に設定する |
| `REDMINE_ROLE` | 送信の再試行を、ジョブを動かすプロセスでだけ有効にする (下記) | ジョブを動かすプロセスでは `worker` |

| 項目 | 説明 | 変える場所 |
| --- | --- | --- |
| 送信元メールアドレス (`Setting.mail_from`) | デフォルトアドレス。検証済みのドメインのもの (例: `noreply@redmine.example.com`) ([receiving.md](receiving.md#address-for-the-whole-redmine)) | Redmine の管理画面の設定 |
| 受信設定 | デフォルトアドレスの `@` の前、そこに届いたメールの扱い、デフォルトのプロジェクト、スパムと DMARC に失敗したメールを取得するか ([admin.md](admin.md#receiving-email)) | プラグインの設定。Serverless では `redmine.json` の `pluginSettings` |
| プロジェクト別のアドレス | 使うか使わないか。デフォルトは使わない (Redmine の標準と同じ)。プロジェクトごとの設定は、各プロジェクトの「メール」のタブ ([admin.md](admin.md#project-email-settings)) | プラグインの設定 |
| 「メール本文から一致する行以降を切り捨てる」 | 引用の前の行。返信の引用が注記に入らないようにする | Redmine の管理画面の設定 |

<a id="receiving-defaults"></a>

### 受信設定のデフォルト値

デフォルトの設定では、デフォルトアドレスの `@` の前は `noreply` で、そこに届いたメールは取得しません (「取得しない」)。取得するときは、「デフォルトのプロジェクトで取得」に切り替えるときに、`@` の前を決めます (例: `redmine`)。受信設定を保存済みの環境では、保存した値のままです。スパム (`import_spam`) と、DMARC に失敗したメール (`import_without_dmarc_pass`) の取得は、どちらもデフォルトはオフです。

<a id="sending-errors"></a>

### 送信エラー

プラグインは、ジョブを動かすプロセス (`REDMINE_ROLE=worker`。Lambda 以外ではポーラーのプロセスに設定する) でだけ、`raise_delivery_errors` を `true` にします。SES のエラーを、Redmine のメールのジョブ (`Mailer::DeliveryJob`) に届けるためです。ほかのプロセスは Redmine の `false` のままなので、1 通の失敗で rake タスクが止まることはありません ([sending.md](sending.md))。

ジョブの中では、エラーの種類で扱いが決まります。一時的なエラーはジョブの中で再試行し、メッセージのエラーはジョブを捨て、アカウントのエラーはキューの再試行とデッドレターキューに任せます ([sending.md](sending.md#handling-by-kind-of-error))。

<a id="importing-received-mail"></a>

### 受信メールの取り込み

rake タスク `redmine_aws_ses:receive_mail` は、受信メールを 1 通取り込みます。そのため、メールごとに何かがこのタスクを起動する必要があります。Lambda では、SES の受信ルールがタスクの関数を非同期で呼び出し、そのハンドラーが SES のイベントの値を変数で渡します ([Serverless の tasks.md](https://redmine-kit.github.io/serverless/ja/tasks.html#kinds-of-events))。

| 変数 | SES のイベントの値 |
| --- | --- |
| `MESSAGE_ID` | `mail.messageId` |
| `SES_RECIPIENTS` | `receipt.recipients` (カンマ区切り) |
| `SES_MAIL_FROM` | `mail.source`。エンベロープの送信者 (登録した転送元のため。省略できる) ([receiving.md](receiving.md#forwarded-email)) |
| `SES_SPAM_VERDICT`<br>`SES_VIRUS_VERDICT`<br>`SES_DMARC_VERDICT`<br>`SES_SPF_VERDICT`<br>`SES_DKIM_VERDICT`<br>`SES_DMARC_POLICY` | 判定の結果 |

取り込むのは、ウイルスの判定が `PASS` で、スパムと DMARC の判定も `PASS` のメールだけです。受信設定で、スパムと DMARC に失敗したメールも取得するようにできます。判定と宛先はイベントから取り、メールのヘッダーからは取りません ([receiving.md](receiving.md#spoofing-and-spam))。

<a id="refreshing-the-ses-state"></a>

### SES の状態の更新

「メール送信」と「メール受信」のタブは、SES の状態 (アカウント、ドメインの ID、サプレッションリスト) とドメインの MX レコードを、このタスクが最後に読んだとおりに出し、画面を開くときに SES や DNS は呼びません ([admin.md](admin.md))。スケジュールで動かします (例: 1 時間に 1 回)。タブの「最新の情報に更新」のリンクも、同じ読み込みをします。読めなかったセクションがあると、タスクは失敗します (エラーはログにあります)。

```sh
bin/rake redmine_aws_ses:refresh
```

<a id="keeping-records"></a>

### 記録の保持

次のタスクが、指定した日数より古い取り込みの記録を消します (デフォルトは 90 日)。Serverless は毎日動かします ([Serverless の security.md](https://redmine-kit.github.io/serverless/ja/security.html#retention-periods))。

```sh
bin/rake redmine_aws_ses:prune_records[<日数>]
```

<a id="aws-resources"></a>

## AWS リソース

| リソース | 設定 |
| --- | --- |
| SES のドメイン ID | Redmine のサブドメイン (例: `redmine.example.com`)。使うリージョンで、Easy DKIM で検証する。送信と受信の両方に使う |
| SES の本稼働アクセス | 前もって申請する (サンドボックスを出る)。リージョンごと |
| DNS | サブドメインの MX を SES の受信エンドポイント (`inbound-smtp.<region>.amazonaws.com`、優先度 10) に向け、Easy DKIM の CNAME を置く ([Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#receiving-domain)) |
| 受信ルール | リージョンのアクティブなルールセットの中。受信者はサブドメイン。TLS は必須。スパムとウイルスの検査は有効。1 つめのアクションで、メールのバケットの `inbound/` に置く。2 つめのアクションで、取り込みを起動する (Lambda では、タスクの関数を非同期で呼び出す) ([Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#receipt-rules)) |
| メールのバケット | `inbound/` (受け取ったもの) と `processed/` (取り込んだもの)。どちらもライフサイクルで 30 日で消す。バケットポリシーで、`inbound/` には SES だけが書けるようにし、TLS でないリクエストを拒否する |

<a id="iam-permissions"></a>

## IAM 権限

プラグインに要る権限と例のポリシーは、[iam.md](iam.md) にあります。

<a id="network"></a>

## ネットワーク

| どこから | どこへ | インターネットに出られない VPC の中では |
| --- | --- | --- |
| Redmine | SES v2 API (`SendEmail`、管理画面) | SES API のインターフェイスエンドポイントか、NAT インスタンス。エンドポイントのサービス名は、作るときに確認する (未確認) |
| Redmine | S3 (メールのバケット) | S3 のゲートウェイエンドポイント (`com.amazonaws.<region>.s3`) |
| 送信者 | SES の受信 (SMTP) | VPC の外。SES が受け取る |

<a id="tests"></a>

## テスト

テストは `test/` にあり、Redmine 標準のしくみで、Docker の中の Redmine 7.0.3 と PostgreSQL 16 で動かします。AWS は、`LOCALSTACK_AUTH_TOKEN` があれば LocalStack です (CI は組織のシークレットを使う)。SES v2 も S3 も LocalStack で動かし、LocalStack が起動しなければ失敗にします。トークンがなければ (フォークからの Pull Request、手元での実行)、同じテストを moto で動かします。ログに使ったほうを出します。

LocalStack が実際の AWS のとおりに再現しない呼び出しは、その呼び出しだけを SDK の応答のスタブ (`stub_responses`) でモックします。

| 呼び出し | モックする理由 | モックした応答 |
| --- | --- | --- |
| SES v2 の `GetAccount` (接続テスト、「メール送信」のタブ) | LocalStack は対応していないと答え、moto にもない (2026-11-09 に確認) | API リファレンスの項目 (`ProductionAccessEnabled`、`SendingEnabled`、`SendQuota` など) と、そのエラー |
| 検証済みの ID でない送信元からの SES v2 の `SendEmail` | 実際の SES は `MessageRejected` で拒むが、LocalStack は送ってしまう | SES のメッセージ (「Email address is not verified. ...」) を持つ `MessageRejected` |
| `SendEmail` の種類別のエラー ([sending.md](sending.md#handling-by-kind-of-error)) | エミュレーターに、スロットリングやアカウントのエラーを返させられない | API リファレンスのそれぞれのエラーコード |

それぞれのテストで確認することは、[sending.md](sending.md#tests) と [receiving.md](receiving.md#tests) にあります。SES のエラーは、SDK の応答のスタブで、配信方法を通して 1 つずつ起こします。画面もスタブを使います。取り込みのテストは、メールをテスト用の S3 (LocalStack か moto) に置き、イベントの判定と宛先といっしょに取り込みます。宛先のプロジェクト、Bcc、プロジェクトを変えられない `Project:` のキーワード、取り込まないそれぞれの理由、何も変えない偽の SES のヘッダー、記録からの再取得を確認します。Redmine のコードローダー (Zeitwerk) が、boot のファイルを先に読み込んだ状態で、Redmine AWS の名前空間の下のプラグインのファイルを読み込めることも、新しいプロセスで確認します (`bin/rails zeitwerk:check`)。`bin/test` は、プラグインのテストのあと、メールのまわりの Redmine 本体のテスト (`MailHandler`、`Mailer`、プロジェクト、設定、管理) を動かします。`bin/test --redmine` は、プラグインをインストールした状態で Redmine 本体のすべてのテストを動かします。CI はこちらです。

CI は、静的チェックとテストを Ruby 3.2 と 4.0 で実行します。ローカルでは、`TEST_RUBY=3.2 bin/test` (または `bin/lint`) で Ruby 3.2 で実行します。

`bin/test-gem` は gem を確認します。チェックアウトからプラグインと Redmine AWS の gem をビルドし、[gem](#gem) のとおりにインストールして `plugins/` にリンクし、すべてのファイルを読み込んで Redmine を起動します (`zeitwerk:check` と、起動時にすべてを読み込む production 環境)。CI もこれを実行するので、gem にないファイルがあれば、Serverless がインストールする前に失敗します。

テストには Redmine AWS が要ります。このリポジトリの隣の [redmine_aws](https://github.com/redmine-kit/redmine_aws) のチェックアウト (`../redmine_aws`) か、`REDMINE_AWS_DIR` に指定したパスです。CI はチェックアウトします。

プラグインのテストは、プラグイン自身のファイルのカバレッジ (SimpleCov。Cobertura XML の `coverage/coverage.xml`) も書きます。CI は、それを [Codecov](https://codecov.io/gh/redmine-kit/redmine_aws_ses) に送ります。

```sh
bin/test            # プラグインのテストと、メールのまわりの Redmine のテスト
bin/test --redmine  # Redmine のすべてのテストも
REDMINE_AWS_DIR=<ディレクトリ> bin/test  # redmine_aws を <ディレクトリ> から
bin/test-gem        # gem をビルド・インストールし、plugins/ にリンクして起動する
bin/lint            # RuboCop
bin/services --down # PostgreSQL、moto、LocalStack を止める
```

<a id="to-verify"></a>

## 未確認の事項

- メッセージ全体を渡す SES v2 の `SendEmail` に、`ses:SendRawEmail` が要るか
- SES API のインターフェイスエンドポイントのサービス名
- SES の SPF の判定が、どの ID を確認するか (RFC 7208 では MAIL FROM の ID。MAIL FROM が空なら HELO の ID)。SES の資料には書かれていない。登録した転送元は、MAIL FROM であることを前提にしている
- Google Workspace の受信者アドレス マップと Gmail の転送で、転送したメッセージのエンベロープの送信者がどうなるか (Google の資料には書かれていない)。登録した転送元に当てはまるかどうか
- Gmail (「転送されたメッセージ」) と Outlook (「差出人:」「送信日時:」「宛先:」「件名:」) の日本語の画面での、転送ブロックの正確な行。資料になく、それらの製品からの転送メールでもまだ確認していない
- メールの設計の、[Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#to-verify) にある項目
