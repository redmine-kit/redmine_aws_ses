# AGENTS.md

Guidelines for people and coding agents working in this repository. See [README.md](README.md) for an overview and [docs/](docs/README.md) for the design.

## What this project does

Redmine Serverless SES (`redmine_serverless_ses`) is a Redmine plugin for sending and receiving Redmine's email with Amazon SES. It works with or without AWS Lambda. [Serverless](https://github.com/redmine-kit/serverless) installs it together with [Redmine Serverless](https://github.com/redmine-kit/redmine_serverless). It is in early development.

## Rules

- **Redmine's extension points only:** do not edit Redmine's own files. Keep Redmine's standard behaviour wherever possible.
- **Off without its settings:** each feature has the condition that turns it on; without it, Redmine behaves as standard.
- **Received email is untrusted:** import only email whose DMARC, spam and virus verdicts in the SES event are `PASS`; take the verdicts and recipients from the event, never from the message's headers.
- **Tests:** replaced and added code has tests, run with Redmine's own mechanism (`bin/test` runs them in Docker with PostgreSQL and moto; [setup.md](docs/setup.md#tests)). What each test checks is in [sending.md](docs/sending.md#tests) and [receiving.md](docs/receiving.md#tests); the order of the tests across the repositories is in Serverless ([testing.md](https://github.com/redmine-kit/serverless/blob/main/docs/testing.md#plugin-tests)).
- **Code layout:** `boot/` holds what must be in place before Rails initializes (Bundler loads it; module `RedmineServerlessSesBoot`), `lib/`, `app/` and `db/` the rest (Redmine loads them; `init.rb` calls `RedmineServerlessSes.setup`).
- **Shared files:** `lib/redmine_serverless_admin.rb`, `app/controllers/serverless_admin_controller.rb` and `app/views/serverless_admin/_tabs.html.erb` are the same in every Redmine Serverless plugin. Change them in all plugins together and raise `SHARED_VERSION`.
- **No secrets in the repository.**

## Documentation

- **Two languages.** English is the source (`README.md`, `docs/`); the Japanese translation is `README.ja.md` and `docs/ja/`, with the same file names. Change both together.
- **Layout.** The READMEs stay short. The details go in `docs/`, published at https://redmine-kit.github.io/redmine_serverless_ses/ with [redmine-kit/docs-skeleton](https://github.com/redmine-kit/docs-skeleton). `docs/README.md` has the overview and the features, `docs/setup.md` the sections Requirements, Installation, Configuration, AWS resources, IAM permissions, Network, Tests and To verify, in this order (the same in every Redmine Serverless plugin; IAM permissions there is one line that points to `docs/iam.md`), `docs/iam.md` the sections Permissions, Example policy, Resource-based policies and Not checked yet. Links to the documentation of Serverless and the other plugins are absolute URLs.
- **Anchors in Japanese.** Put `<a id="..."></a>` with the English heading's anchor before each Japanese heading.
- **Facts.** State only what has been checked, with the date and the source. Mark what has not been checked yet.
- **Japanese wording.** Plain, precise Japanese. Keep established technical terms. Do not use "版" for a version, write "通知" rather than "知らせ", "確認" rather than "確かめ", and "インストール" rather than "入れ方".

## Commits

- English, imperative mood, 72 characters or fewer in the first line, no trailing period.
- One purpose per commit.
- Do not rewrite pushed history.
