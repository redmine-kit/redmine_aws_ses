# AGENTS.md

Guidelines for people and coding agents working in this repository. See [README.md](README.md) for an overview and [docs/](docs/README.md) for the design.

## What this project does

Redmine Kit AWS SES (`redmine_kit_aws_ses`) is a Redmine plugin for sending and receiving Redmine's email with Amazon SES. It works with or without AWS Lambda. It requires [Redmine Kit AWS](https://github.com/redmine-kit/redmine_aws) (`redmine_kit_aws`). [Serverless](https://github.com/redmine-kit/serverless) installs it together with [Redmine Kit AWS Lambda](https://github.com/redmine-kit/redmine_aws_lambda). It is in early development.

## Rules

- **Redmine's extension points only:** do not edit Redmine's own files. Keep Redmine's standard behaviour wherever possible.
- **Off without its settings:** each feature has the condition that turns it on; without it, Redmine behaves as standard.
- **Received email is untrusted:** import only email whose DMARC, spam and virus verdicts in the SES event are `PASS`; take the verdicts and recipients from the event, never from the message's headers.
- **Tests:** replaced and added code has tests, run with Redmine's own mechanism (`bin/test` runs them in a container (Apple container, else Docker) with PostgreSQL, S3 on AWS Emulator, and SES sending on LocalStack, or moto without a LocalStack token; [setup.md](docs/setup.md#tests)). What each test checks is in [sending.md](docs/sending.md#tests) and [receiving.md](docs/receiving.md#tests); the order of the tests across the repositories is in Serverless ([testing.md](https://github.com/redmine-kit/serverless/blob/main/docs/testing.md#plugin-tests)).
- **Code layout:** `boot/` holds what must be in place before Rails initializes (Bundler loads it; module `RedmineKit::Aws::Ses::Boot`), `lib/`, `app/` and `db/` the rest (Redmine loads them; `init.rb` calls `RedmineKit::Aws::Ses.setup`). The code is in the namespace of redmine_kit_aws: `lib/redmine_kit/aws/ses.rb` defines `RedmineKit::Aws::Ses` and `lib/redmine_kit/aws/ses/` the rest; refer to the AWS SDK as `::Aws::…`. Don't add other files directly in `lib/redmine_kit/aws/`: they belong to redmine_kit_aws.
- **Requires redmine_kit_aws:** the "AWS" item of the administration menu with its tabs and connection checks, the settings of the AWS clients and the test support come from [redmine_kit_aws](https://github.com/redmine-kit/redmine_aws) (`RedmineKit::Aws::Admin`, `RedmineKit::Aws::AdminTab`, `RedmineKit::Aws.client`, `RedmineKit::Aws::TestHelper`, `RedmineKit::Aws::ScreenshotCase`). Don't copy them into this plugin. `bin/test` and `bin/screenshots` load redmine_kit_aws from `../redmine_kit_aws`, or from `REDMINE_KIT_AWS_DIR`.
- **No secrets in the repository.**

## Documentation

- **Two languages.** English is the source (`README.md`, `docs/`); the Japanese translation is `README.ja.md` and `docs/ja/`, with the same file names. Change both together.
- **Layout.** The READMEs stay short. The details go in `docs/`, published at https://redmine-kit.github.io/redmine_aws_ses/ with [redmine-kit/docs-skeleton](https://github.com/redmine-kit/docs-skeleton). `docs/README.md` has the overview and the features, `docs/setup.md` the sections Requirements, Installation, Configuration, AWS resources, IAM permissions, Network, Tests and To verify, in this order (the same in every Redmine Kit AWS plugin; IAM permissions there is one line that points to `docs/iam.md`), `docs/iam.md` the sections Permissions, Example policy, Resource-based policies and Not checked yet. Links to the documentation of Serverless and the other plugins are absolute URLs.
- **Anchors in Japanese.** Put `<a id="..."></a>` with the English heading's anchor before each Japanese heading.
- **Facts.** State only what has been checked, with the date and the source. Mark what has not been checked yet.
- **Japanese wording.** Plain, precise Japanese. Keep established technical terms. Do not use "版" for a version, write "通知" rather than "知らせ", "確認" rather than "確かめ", and "インストール" rather than "入れ方".

## Commits

- English, imperative mood, 72 characters or fewer in the first line, no trailing period.
- One purpose per commit.
- Do not rewrite pushed history.

## Development environment

- **Apple container first, Docker too** (a public repository). Scripts (`bin/test`, databases, emulators) use Apple container (`container`) when it is installed and running, else Docker (other machines, CI); `CONTAINER_CLI=docker|container` chooses. Docs give both, Apple container first. Images are built from the `Dockerfile` with either tool. In Apple container, the test containers run on the networks that every repository shares, `redmine-kit-test` and `redmine-kit-test-internal` (no way out), each with an anchor container that runs all the time (`ensure_shared_network` in `bin/container_cli`; apple/container#2051, until macOS 27.3; the organization's `../AGENTS.md`). Docker keeps a Compose network per repository.
- **Libraries at their latest versions.** Dependencies are kept at their latest stable releases, pinned exactly in the lockfiles; a version held back has its reason next to the pin.
- Both are the organization's rules (`../AGENTS.md`, "Development environment").
