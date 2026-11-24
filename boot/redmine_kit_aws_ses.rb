# frozen_string_literal: true

# Redmine Kit AWS SES as a gem (docs/setup.md#installation): Bundler requires this file
# when Redmine's Gemfile.local has `gem 'redmine_kit_aws_ses'`, or (with a checkout in
# plugins/) the plugin's Gemfile names it by path.
#
# Redmine 7.0.3 loads plugins from its plugins/ folder only
# (Redmine::PluginLoader). This hands the gem's folder to the same loader,
# after Redmine's initializers have listed plugins/: Redmine then runs
# init.rb (which registers the plugin with this folder, `directory`) and
# serves its assets, locales, views and migrations as for any plugin; the
# folder's lib/ and app/ go to Rails' code loader (Zeitwerk) as Redmine adds a
# plugin's (PluginLoader.add_autoload_paths); its routes come after Redmine's,
# as Redmine draws a plugin's. A plugin of the same id in plugins/ (a checkout
# or a link) wins, and nothing is done (redmine_kit_ui's template,
# examples/redmine_kit_example).
#
# The part of Redmine Kit AWS SES that must be in place before Rails finishes
# initializing: the SES delivery method (:ses_v2, registered by
# aws-actionmailer-ses) and the interceptor that sets per-project senders.
# Bundler loads this file (the plugin is also a gem); init.rb, which Redmine
# runs later, does the rest. It is outside lib/, which Redmine autoloads. It
# defines only RedmineKit::Aws::Ses::Boot: the modules around it are empty
# and nested here (RedmineKit belongs to no plugin), and lib/redmine_kit/aws.rb
# and lib/redmine_kit/aws/ses.rb, which the code loader then skips, are
# loaded by the init.rb files.
require 'aws-actionmailer-ses'
require 'aws-sdk-s3'

require 'active_support/lazy_load_hooks'
# The gems of the plugins it requires (config/dependencies.yml): Bundler
# installs them with this one, and their boot files hand their folders to
# Redmine's plugin loader too.
require 'yaml'
YAML.safe_load_file(File.expand_path('../config/dependencies.yml', __dir__))['requires'].each_key do |name|
  require name
end

ActiveSupport.on_load(:before_configuration, yield: true) do |app|
  dir = File.expand_path('..', __dir__)
  app.initializer 'redmine_kit_aws_ses.gem', after: :load_config_initializers do |application|
    loader = Redmine::PluginLoader
    next if loader.directories.any? { |path| File.basename(path.to_s) == 'redmine_kit_aws_ses' }

    loader.directories << Redmine::PluginPath.new(dir)
    Rails::Engine::Configuration.new(dir).tap { |config| config.paths.add 'lib', eager_load: true }
                                .all_eager_load_paths.each do |path|
      Rails.autoloaders.main.push_dir(path)
      application.config.watchable_dirs[path] = [:rb]
    end
    routes = File.join(dir, 'config/routes.rb')
    application.routes.append { instance_eval(File.read(routes), routes) } if File.file?(routes)
  end
end

module RedmineKit
  module Aws
    module Ses
      module Boot
        # Registered once; it calls the reloadable code in lib/.
        module Interceptor
          def self.delivering_email(message)
            RedmineKit::Aws::Ses::ProjectSender.call(message)
          end
        end

        if defined?(Rails::Railtie)
          class Railtie < Rails::Railtie
            config.after_initialize do
              ActionMailer::Base.register_interceptor(RedmineKit::Aws::Ses::Boot::Interceptor)
            end
          end
        end
      end
    end
  end
end
