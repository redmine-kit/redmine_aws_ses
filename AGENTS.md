# AGENTS.md

Guidelines for people and coding agents working in this repository. See [README.md](README.md) for an overview and [docs/](docs/README.md) for the design.

## What this project does

Redmine AWS SES (`redmine_aws_ses`) is a Redmine plugin for sending and receiving Redmine's email with Amazon SES. It works with or without AWS Lambda. It requires [Redmine AWS](https://github.com/redmine-kit/redmine_aws) (`redmine_aws`). [Serverless](https://github.com/redmine-kit/serverless) installs it together with [Redmine AWS Lambda](https://github.com/redmine-kit/redmine_aws_lambda). It is in early development.

## Rules

- **Redmine's extension points only:** do not edit Redmine's own files. Keep Redmine's standard behaviour wherever possible.
- **Off without its settings:** each feature has the condition that turns it on; without it, Redmine behaves as standard.
- **Received email is untrusted:** import only email whose DMARC, spam and virus verdicts in the SES event are `PASS`; take the verdicts and recipients from the event, never from the message's headers.
- **Tests:** replaced and added code has tests, run with Redmine's own mechanism (`bin/test` runs them in Docker with PostgreSQL and LocalStack, or moto without a LocalStack token; [setup.md](docs/setup.md#tests)). What each test checks is in [sending.md](docs/sending.md#tests) and [receiving.md](docs/receiving.md#tests); the order of the tests across the repositories is in Serverless ([testing.md](https://github.com/redmine-kit/serverless/blob/main/docs/testing.md#plugin-tests)).
- **Code layout:** `boot/` holds what must be in place before Rails initializes (Bundler loads it; module `RedmineAws::SES::Boot`), `lib/`, `app/` and `db/` the rest (Redmine loads them; `init.rb` calls `RedmineAws::SES.setup`). The code is in the namespace of redmine_aws: `lib/redmine_aws/ses.rb` defines `RedmineAws::SES` and `lib/redmine_aws/ses/` the rest; refer to the AWS SDK as `::Aws::…`. Don't add other files directly in `lib/redmine_aws/`: they belong to redmine_aws.
- **Requires redmine_aws:** the "AWS" item of the administration menu with its tabs and connection checks, the settings of the AWS clients and the test support come from [redmine_aws](https://github.com/redmine-kit/redmine_aws) (`RedmineAws::Admin`, `RedmineAws::AdminTab`, `RedmineAws.client`, `RedmineAws::TestHelper`, `RedmineAws::ScreenshotCase`). Don't copy them into this plugin. `bin/test` and `bin/screenshots` load redmine_aws from `../redmine_aws`, or from `REDMINE_AWS_DIR`.
- **No secrets in the repository.**

## Documentation

- **Two languages.** English is the source (`README.md`, `docs/`); the Japanese translation is `README.ja.md` and `docs/ja/`, with the same file names. Change both together.
- **Layout.** The READMEs stay short. The details go in `docs/`, published at https://redmine-kit.github.io/redmine_aws_ses/ with [redmine-kit/docs-skeleton](https://github.com/redmine-kit/docs-skeleton). `docs/README.md` has the overview and the features, `docs/setup.md` the sections Requirements, Installation, Configuration, AWS resources, IAM permissions, Network, Tests and To verify, in this order (the same in every Redmine AWS plugin; IAM permissions there is one line that points to `docs/iam.md`), `docs/iam.md` the sections Permissions, Example policy, Resource-based policies and Not checked yet. Links to the documentation of Serverless and the other plugins are absolute URLs.
- **Anchors in Japanese.** Put `<a id="..."></a>` with the English heading's anchor before each Japanese heading.
- **Facts.** State only what has been checked, with the date and the source. Mark what has not been checked yet.
- **Japanese wording.** Plain, precise Japanese. Keep established technical terms. Do not use "版" for a version, write "通知" rather than "知らせ", "確認" rather than "確かめ", and "インストール" rather than "入れ方".

## Commits

- English, imperative mood, 72 characters or fewer in the first line, no trailing period.
- One purpose per commit.
- Do not rewrite pushed history.
