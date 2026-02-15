# frozen_string_literal: true

require "open3"
require "fileutils"

module Gem
  module Update
    class Sandbox
      attr_reader :before_url, :after_url

      def initialize(gem_name, config:, log_dir:)
        @config = config
        @log_dir = log_dir
        base = config.database_url_base
        pid = Process.pid
        @before_db = "gem_update_#{gem_name}_before_#{pid}"
        @after_db = "gem_update_#{gem_name}_after_#{pid}"
        @before_url = "#{base}/#{@before_db}"
        @after_url = "#{base}/#{@after_db}"
      end

      def setup(directory:, database_url:)
        env = base_env.merge("DATABASE_URL" => database_url)

        run_command("bundle", "exec", "rails", "db:create", dir: directory, env: env, label: "db_create")
        run_command("bundle", "exec", "rails", "db:schema:load", dir: directory, env: env, label: "db_schema_load")

        if @config.setup_task
          run_command("bundle", "exec", "rails", @config.setup_task, dir: directory, env: env, label: "setup_task")
        end

        return unless @config.setup_script

        run_command("bundle", "exec", "ruby", @config.setup_script, dir: directory, env: env, label: "setup_script")
      end

      def cleanup(directory:, database_url:)
        env = base_env.merge(
          "DATABASE_URL" => database_url,
          "DISABLE_DATABASE_ENVIRONMENT_CHECK" => "1"
        )
        run_command("bundle", "exec", "rails", "db:drop", dir: directory, env: env, label: "db_drop")
      end

      private

      def base_env
        { "RAILS_ENV" => @config.rails_env, "RACK_ENV" => @config.rails_env }
      end

      def run_command(*cmd, dir:, env:, label:)
        FileUtils.mkdir_p(@log_dir)

        stdout, stderr, status = Bundler.with_unbundled_env do
          Open3.capture3(env, *cmd, chdir: dir)
        end

        File.write(File.join(@log_dir, "#{label}_stdout.log"), stdout)
        File.write(File.join(@log_dir, "#{label}_stderr.log"), stderr)

        return if status.success?

        raise "Sandbox command failed: #{cmd.join(" ")} (exit #{status.exitstatus}). " \
              "Check #{@log_dir}/#{label}_stderr.log"
      end
    end
  end
end
