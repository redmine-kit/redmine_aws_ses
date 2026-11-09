# frozen_string_literal: true

# The plugin as a gem, published to GitHub Packages (.github/workflows/gem.yml).
# The gem holds the plugin's run-time files, so that the installed gem can be
# linked into Redmine's plugins/ (docs/setup.md#installation). The plugin's
# Gemfile is not in it: Redmine's Gemfile would load it again.
Gem::Specification.new do |spec|
  spec.name = 'redmine_serverless_ses'
  spec.version = '0.1.0'
  spec.summary = 'Sends and receives Redmine email with Amazon SES'
  spec.authors = ['Redmine Kit']
  spec.license = 'GPL-2.0-or-later'
  spec.homepage = 'https://github.com/redmine-kit/redmine_serverless_ses'
  spec.required_ruby_version = '>= 4.0'
  spec.files = Dir['{init.rb,LICENSE}', '{app,assets,config,db,lib}/**/*']
  spec.metadata['github_repo'] = 'ssh://github.com/redmine-kit/redmine_serverless_ses'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
