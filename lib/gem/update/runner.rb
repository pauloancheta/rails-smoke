# frozen_string_literal: true

require "fileutils"

module Gem
  module Update
    class Runner
      def initialize(gem_name, config: nil)
        @gem_name = gem_name
        @config = config || Config.new(gem_name)
        @output_dir = File.join("tmp", "gem_updates", gem_name)
      end

      def run
        setup_output_dir

        puts "== gem-update: #{@gem_name} =="
        puts ""

        puts "1. Creating worktree..."
        worktree = Worktree.new(@gem_name, base_dir: @output_dir)
        worktree.create

        puts "2. Running bundle update #{@gem_name}..."
        updater = GemUpdater.new(@gem_name, worktree_path: worktree.path, output_dir: @output_dir)
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
        before_server = PumaServer.new(port: @config.before_port, log_dir: File.join(@output_dir, "before"))
        after_server = PumaServer.new(port: @config.after_port, log_dir: File.join(@output_dir, "after"))
        servers = [before_server, after_server]

        previous_int = Signal.trap("INT") do
          shutdown_servers(servers)
          exit(1)
        end
        previous_term = Signal.trap("TERM") do
          shutdown_servers(servers)
          exit(1)
        end

        begin
          puts "   Starting puma servers..."
          before_server.start(directory: Dir.pwd)
          puts "   Before server running on port #{@config.before_port}"

          after_server.start(directory: worktree.path)
          puts "   After server running on port #{@config.after_port}"

          puts "3. Running smoke tests (before & after in parallel)..."
          smoke = SmokeTest.new(@gem_name)
          before_env = { "SERVER_PORT" => @config.before_port.to_s }
          after_env = { "SERVER_PORT" => @config.after_port.to_s }

          before_thread = Thread.new do
            smoke.run(directory: Dir.pwd, output_dir: File.join(@output_dir, "before"), env: before_env)
          end

          after_thread = Thread.new do
            smoke.run(directory: worktree.path, output_dir: File.join(@output_dir, "after"), env: after_env)
          end

          [before_thread.value, after_thread.value]
        ensure
          shutdown_servers(servers)
          Signal.trap("INT", previous_int || "DEFAULT")
          Signal.trap("TERM", previous_term || "DEFAULT")
        end
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
