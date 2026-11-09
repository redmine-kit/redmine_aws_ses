# AGENTS.md

Guidelines for people and coding agents working in this repository. See [README.md](README.md) for an overview and [docs/](docs/README.md) for the design.

## What this project does

Redmine Serverless SES (`redmine_serverless_ses`) is a Redmine plugin for sending and receiving Redmine's email with Amazon SES. It works with or without AWS Lambda. [Serverless](https://github.com/redmine-kit/serverless) installs it together with [Redmine Serverless](https://github.com/redmine-kit/redmine_serverless). It is in the design stage: the repository holds the design documents.

## Rules

- **Redmine's extension points only:** do not edit Redmine's own files. Keep Redmine's standard behaviour wherever possible.
- **Off without its settings:** each feature has the condition that turns it on; without it, Redmine behaves as standard.
- **Received email is untrusted:** import only email that passes DMARC and SES's spam and virus verdicts, and never trust `X-SES-*` headers added by the sender.
- **Tests:** replaced and added code has tests, run with Redmine's own mechanism (`rake redmine:plugins:test`). The test plan is in Serverless ([testing.md](https://github.com/redmine-kit/serverless/blob/main/docs/testing.md#running-on-lambda-and-email)).
- **No secrets in the repository.**

## Documentation

- **Two languages.** English is the source (`README.md`, `docs/`); the Japanese translation is `README.ja.md` and `docs/ja/`, with the same file names. Change both together.
- **Layout.** The READMEs stay short. The details go in `docs/`, published at https://redmine-kit.github.io/redmine_serverless_ses/ with [redmine-kit/docs-skeleton](https://github.com/redmine-kit/docs-skeleton). Links to the documentation of Serverless and the other plugins are absolute URLs.
- **Anchors in Japanese.** Put `<a id="..."></a>` with the English heading's anchor before each Japanese heading.
- **Facts.** State only what has been checked, with the date and the source. Mark what has not been checked yet.
- **Japanese wording.** Plain, precise Japanese. Keep established technical terms. Do not use "版" for a version, write "通知" rather than "知らせ", and "確認" rather than "確かめ".

## Commits

- English, imperative mood, 72 characters or fewer in the first line, no trailing period.
- One purpose per commit.
- Do not rewrite pushed history.
