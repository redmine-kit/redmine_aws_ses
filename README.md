# Redmine Serverless SES

[![CI](https://img.shields.io/github/actions/workflow/status/redmine-kit/redmine_serverless_ses/ci.yml?branch=main&label=CI)](https://github.com/redmine-kit/redmine_serverless_ses/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/codecov/c/github/redmine-kit/redmine_serverless_ses?label=Coverage)](https://codecov.io/gh/redmine-kit/redmine_serverless_ses)
[![License](https://img.shields.io/github/license/redmine-kit/redmine_serverless_ses?label=License)](LICENSE)

A Redmine plugin for sending and receiving Redmine's email with Amazon SES: retries of sending by error type, importing received email with checks against spoofing and spam, email addresses per project, and administration pages for SES. It works with or without AWS Lambda; [Serverless](https://github.com/redmine-kit/serverless) uses it together with [Redmine Serverless](https://github.com/redmine-kit/redmine_serverless).

[日本語](README.ja.md)

> **Status:** early development. Sending with retries by error type, importing with the checks of SES, addresses per project and the administration pages are implemented and tested on Redmine 7.0.3 with moto.

## Documentation

- Website: https://redmine-kit.github.io/redmine_serverless_ses/ (日本語: https://redmine-kit.github.io/redmine_serverless_ses/ja/)
- Markdown: [docs/README.md](docs/README.md) (日本語: [docs/ja/README.md](docs/ja/README.md)), with [setup](docs/setup.md), [IAM permissions](docs/iam.md) and the [administration pages](docs/admin.md)

## License

Redmine Serverless SES is released under the GNU General Public License, version 2 or (at your option) any later version. See [LICENSE](LICENSE). Not affiliated with the Redmine project.
