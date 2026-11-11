# syntax=docker/dockerfile:1
# Redmine 7.0.3 with this plugin and redmine_aws, which it requires, for the
# tests (bin/test). Built from the repository root, with redmine_aws as the
# build context of that name:
#   docker buildx build --build-context redmine_aws=../redmine_aws -f test/Dockerfile .
FROM ruby:4.0@sha256:a69f361db050bb2c65ec66ef75411bfc4ce2e1d993ba1179fac4e4ba6ecfe91f
# Ghostscript for Redmine's tests that export PDF and PNG.
RUN apt-get update && apt-get install -y --no-install-recommends ghostscript && rm -rf /var/lib/apt/lists/*
ARG REDMINE_VERSION=7.0.3
ARG REDMINE_SHA256=0b6b24c033341a9d7ad52cfcfa7b1bc913c191c7a604f740d863f16249dd3c15
RUN curl -fsSLo /tmp/redmine.tar.gz "https://www.redmine.org/releases/redmine-${REDMINE_VERSION}.tar.gz" \
  && echo "${REDMINE_SHA256}  /tmp/redmine.tar.gz" | sha256sum -c - \
  && tar -xzf /tmp/redmine.tar.gz -C / \
  && mv "/redmine-${REDMINE_VERSION}" /redmine \
  && rm /tmp/redmine.tar.gz
WORKDIR /redmine
COPY test/database.yml config/database.yml
COPY --from=redmine_aws . plugins/redmine_aws/
COPY . plugins/redmine_aws_ses/
# The plugin as a gem by path, so that Bundler loads boot/ (docs/setup.md),
# and redmine_aws, which its gemspec requires, by path without loading it.
RUN printf "gem 'redmine_aws', path: 'plugins/redmine_aws', require: false\ngem 'redmine_aws_ses', path: 'plugins/redmine_aws_ses'\ngem 'simplecov-cobertura', group: :test\n" > Gemfile.local \
  && bundle config set --local without development \
  && bundle install --jobs 4
ENV RAILS_ENV=test
# AWS is moto (test/compose.yml).
ENV AWS_ENDPOINT_URL=http://moto:5000 AWS_REGION=us-east-1 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
