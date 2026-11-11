# frozen_string_literal: true

# The plugin as a gem, published to GitHub Packages (.github/workflows/gem.yml).
# The gem holds the plugin's run-time files, so that the installed gem can be
# linked into Redmine's plugins/ (docs/setup.md#installation). The plugin's
# Gemfile is not in it: Redmine's Gemfile would load it again.
Gem::Specification.new do |spec|
  spec.name = 'redmine_aws_ses'
  spec.version = File.read(File.join(__dir__, 'lib/redmine_aws/ses.rb'))[/VERSION = '([^']+)'/, 1]
  spec.summary = 'Sends and receives Redmine email with Amazon SES'
  spec.authors = ['Redmine Kit']
  spec.license = 'GPL-2.0-or-later'
  spec.homepage = 'https://github.com/redmine-kit/redmine_aws_ses'
  # The Ruby versions of Redmine 7.0 (its Gemfile: ruby '>= 3.2.0', '< 4.1.0').
  spec.required_ruby_version = '>= 3.2'
  spec.files = Dir['{init.rb,LICENSE}', '{app,boot,config,db,lib,help}/**/*']
  # boot/ holds what Bundler loads before Rails initializes; lib/ is Redmine's
  # (autoloaded) and must not be required by Bundler.
  spec.require_paths = ['boot']
  spec.add_dependency 'aws-actionmailer-ses', '~> 1.2'
  spec.add_dependency 'aws-sdk-s3', '~> 1.0'
  spec.add_dependency 'aws-sdk-sesv2', '~> 1.0'
  spec.add_dependency 'redmine_aws', '~> 0.1'
  spec.metadata['github_repo'] = 'ssh://github.com/redmine-kit/redmine_aws_ses'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
