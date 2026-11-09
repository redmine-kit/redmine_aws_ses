# Redmine Serverless SES

[![CI](https://img.shields.io/github/actions/workflow/status/redmine-kit/redmine_serverless_ses/ci.yml?branch=main&label=CI)](https://github.com/redmine-kit/redmine_serverless_ses/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/codecov/c/github/redmine-kit/redmine_serverless_ses?label=Coverage)](https://codecov.io/gh/redmine-kit/redmine_serverless_ses)
[![License](https://img.shields.io/github/license/redmine-kit/redmine_serverless_ses?label=License)](LICENSE)

Redmine のメールを Amazon SES で送受信するための Redmine のプラグインです。エラーの種類ごとの送信のやり直し、なりすましと迷惑メールの確認を付けた受信の取り込み、プロジェクトごとのメールアドレス、SES の管理画面を持ちます。AWS Lambda でも、Lambda 以外でも動きます。[Serverless](https://github.com/redmine-kit/serverless) は、[Redmine Serverless](https://github.com/redmine-kit/redmine_serverless) といっしょに使います。

[English](README.md)

> **状態:** 開発の初期です。エラーの種類ごとにやり直す送信、SES の確認の結果を使う取り込み、プロジェクトごとのアドレス、管理画面を実装し、Redmine 7.0.3 と moto でテストしています。

<a id="documentation"></a>

## ドキュメント

- Web サイト: https://redmine-kit.github.io/redmine_serverless_ses/ja/ (English: https://redmine-kit.github.io/redmine_serverless_ses/)
- Markdown: [docs/ja/README.md](docs/ja/README.md) (English: [docs/README.md](docs/README.md))。[準備](docs/ja/setup.md)、[IAM の権限](docs/ja/iam.md)と[管理画面](docs/ja/admin.md)があります。

<a id="license"></a>

## ライセンス

Redmine Serverless SES は、GNU General Public License バージョン 2 またはそれ以降のバージョンで公開しています。[LICENSE](LICENSE) を参照してください。Redmine projectとは関係ありません。
