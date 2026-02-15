# frozen_string_literal: true

require "fileutils"

module Gem
  module Update
    class Runner # rubocop:disable Metrics/ClassLength
      def initialize(config:)
        @config = config
        @gem_name = config.gem_name
        @output_dir = File.join("tmp", "gem_updates", @gem_name)
      end

      def run
        setup_output_dir

        puts "== gem-update: #{@gem_name} =="
        puts ""

        puts "1. Creating worktree..."
        worktree = Worktree.new(@gem_name, base_dir: @output_dir)
        worktree.create

        version_label = @config.version ? " to #{@config.version}" : ""
        puts "2. Running bundle update #{@gem_name}#{version_label}..."
        updater = GemUpdater.new(@gem_name, worktree_path: worktree.path, output_dir: @output_dir,
                                            version: @config.version)
        unless updater.run
          warn "bundle update #{@gem_name} failed. Check #{@output_dir}/bundle_update.log"
          cleanup(worktree)
          exit 1
        end

        before_result, after_result = if @config.server?
                                        run_with_servers(worktree)
                                      else
                                        run_without_servers(worktree)
                                      end

        puts "5. Generating report..."
        report = Report.new(@gem_name, before: before_result, after: after_result, output_dir: @output_dir)
        report.generate

        cleanup(worktree)
      end

      private

      def run_with_servers(worktree)
        sandbox, before_env, after_env = setup_sandbox(worktree)

        before_server = PumaServer.new(port: @config.before_port, log_dir: File.join(@output_dir, "before"),
                                       env: before_env)
        after_server = PumaServer.new(port: @config.after_port, log_dir: File.join(@output_dir, "after"),
                                      env: after_env)
        servers = [before_server, after_server]

        with_signal_handlers(servers) do
          start_servers(before_server, after_server, worktree)
          run_smoke_tests_parallel(worktree)
        ensure
          shutdown_servers(servers)
          cleanup_sandbox(sandbox, worktree)
        end
      end

      def setup_sandbox(worktree)
        before_env = { "RAILS_ENV" => @config.rails_env, "RACK_ENV" => @config.rails_env }
        after_env = { "RAILS_ENV" => @config.rails_env, "RACK_ENV" => @config.rails_env }
        sandbox = nil

        if @config.sandbox?
          sandbox = Sandbox.new(@gem_name, config: @config, log_dir: File.join(@output_dir, "sandbox"))
          puts "   Setting up sandbox databases..."
          sandbox.setup(directory: Dir.pwd, database_url: sandbox.before_url)
          sandbox.setup(directory: worktree.path, database_url: sandbox.after_url)
          before_env["DATABASE_URL"] = sandbox.before_url
          after_env["DATABASE_URL"] = sandbox.after_url
        end

        [sandbox, before_env, after_env]
      end

      def start_servers(before_server, after_server, worktree)
        puts "   Starting puma servers..."
        before_server.start(directory: Dir.pwd)
        puts "   Before server running on port #{@config.before_port} (#{@config.rails_env})"
        after_server.start(directory: worktree.path)
        puts "   After server running on port #{@config.after_port} (#{@config.rails_env})"
      end

      def run_smoke_tests_parallel(worktree)
        puts "3. Running smoke tests (before & after in parallel)..."
        smoke = SmokeTest.new(@gem_name)

        before_thread = Thread.new do
          smoke.run(directory: Dir.pwd, output_dir: File.join(@output_dir, "before"),
                    server_port: @config.before_port)
        end
        after_thread = Thread.new do
          smoke.run(directory: worktree.path, output_dir: File.join(@output_dir, "after"),
                    server_port: @config.after_port)
        end

        [before_thread.value, after_thread.value]
      end

      def with_signal_handlers(servers)
        previous_int = Signal.trap("INT") do
          shutdown_servers(servers)
          exit(1)
        end
        previous_term = Signal.trap("TERM") do
          shutdown_servers(servers)
          exit(1)
        end
        yield
      ensure
        Signal.trap("INT", previous_int || "DEFAULT")
        Signal.trap("TERM", previous_term || "DEFAULT")
      end

      def cleanup_sandbox(sandbox, worktree)
        return unless sandbox

        puts "   Cleaning up sandbox databases..."
        sandbox.cleanup(directory: Dir.pwd, database_url: sandbox.before_url)
        sandbox.cleanup(directory: worktree.path, database_url: sandbox.after_url)
      end

      def run_without_servers(worktree)
        puts "3. Running smoke tests (before)..."
        smoke = SmokeTest.new(@gem_name)
        before_result = smoke.run(directory: Dir.pwd, output_dir: File.join(@output_dir, "before"))

        puts "4. Running smoke tests (after)..."
        after_result = smoke.run(directory: worktree.path, output_dir: File.join(@output_dir, "after"))

        [before_result, after_result]
      end

      def setup_output_dir
        PumaServer.cleanup_stale(@output_dir) if File.directory?(@output_dir)
        FileUtils.rm_rf(@output_dir)
        FileUtils.mkdir_p(@output_dir)
      end

      def shutdown_servers(servers)
        servers.each(&:stop)
      end

      def cleanup(worktree)
        worktree.remove
      end
    end
  end
end
