# frozen_string_literal: true

require "fileutils"
require "open3"

module RailsSmoke
  class Runner # rubocop:disable Metrics/ClassLength
    def initialize(config:)
      @config = config
      @identifier = config.identifier
      @output_dir = File.join("tmp", "rails_smoke", @identifier)
    end

    def run
      setup_output_dir

      puts "== rails-smoke: #{@identifier} =="
      puts ""

      if @config.mode == "branch"
        run_branch_mode
      else
        run_gem_mode
      end
    end

    private

    def run_gem_mode
      puts "1. Creating worktree..."
      worktree = Worktree.new(@identifier, base_dir: @output_dir)
      worktree.create

      version_label = @config.version ? " to #{@config.version}" : ""
      puts "2. Running bundle update #{@identifier}#{version_label}..."
      updater = GemUpdater.new(@identifier, worktree_path: worktree.path, output_dir: @output_dir,
                                            version: @config.version)
      unless updater.run
        warn "bundle update #{@identifier} failed. Check #{@output_dir}/bundle_update.log"
        exit 1
      end

      before_result, after_result = if @config.server?
                                      run_with_servers(worktree)
                                    else
                                      run_without_servers(worktree)
                                    end

      puts "5. Generating report..."
      report = Report.new(@identifier, before: before_result, after: after_result, output_dir: @output_dir)
      report.generate
      html_report = HtmlReport.new(@identifier, before: before_result, after: after_result, output_dir: @output_dir)
      html_report.generate
    ensure
      cleanup(worktree) if worktree
    end

    def run_branch_mode
      puts "1. Creating worktree for #{@config.before_branch}..."
      worktree = Worktree.new(@identifier, base_dir: @output_dir, suffix: "before_worktree")
      worktree.create(ref: @config.before_branch)

      puts "2. Generating Gemfile.lock diff..."
      generate_lock_diff(worktree.path, Dir.pwd)

      before_result, after_result = if @config.server?
                                      run_branch_with_servers(worktree)
                                    else
                                      run_branch_without_servers(worktree)
                                    end

      puts "5. Generating report..."
      report = Report.new(@identifier, before: before_result, after: after_result, output_dir: @output_dir)
      report.generate
      html_report = HtmlReport.new(@identifier, before: before_result, after: after_result, output_dir: @output_dir)
      html_report.generate
    ensure
      cleanup(worktree) if worktree
    end

    def run_branch_with_servers(worktree)
      sandbox, before_env, after_env = setup_branch_sandbox(worktree)

      before_server = PumaServer.new(port: @config.before_port, log_dir: File.join(@output_dir, "before"),
                                     env: before_env)
      after_server = PumaServer.new(port: @config.after_port, log_dir: File.join(@output_dir, "after"),
                                    env: after_env)
      servers = [before_server, after_server]

      with_signal_handlers(servers) do
        puts "   Starting puma servers..."
        before_server.start(directory: worktree.path)
        puts "   Before server running on port #{@config.before_port} (#{@config.rails_env})"
        after_server.start(directory: Dir.pwd)
        puts "   After server running on port #{@config.after_port} (#{@config.rails_env})"

        run_branch_smoke_tests_parallel(worktree)
      ensure
        shutdown_servers(servers)
        cleanup_branch_sandbox(sandbox, worktree)
      end
    end

    def setup_branch_sandbox(worktree)
      before_env = { "RAILS_ENV" => @config.rails_env, "RACK_ENV" => @config.rails_env }
      after_env = { "RAILS_ENV" => @config.rails_env, "RACK_ENV" => @config.rails_env }
      sandbox = nil

      if @config.sandbox?
        sandbox = Sandbox.new(@identifier, config: @config, log_dir: File.join(@output_dir, "sandbox"))
        puts "   Setting up sandbox databases..."
        sandbox.setup(directory: worktree.path, database_url: sandbox.before_url)
        sandbox.setup(directory: Dir.pwd, database_url: sandbox.after_url)
        before_env["DATABASE_URL"] = sandbox.before_url
        after_env["DATABASE_URL"] = sandbox.after_url
      end

      [sandbox, before_env, after_env]
    end

    def run_branch_smoke_tests_parallel(worktree)
      puts "3. Running smoke tests (before & after in parallel)..."
      smoke = SmokeTest.new(@identifier)

      before_thread = Thread.new do
        smoke.run(directory: worktree.path, output_dir: File.join(@output_dir, "before"),
                  server_port: @config.before_port)
      end
      after_thread = Thread.new do
        smoke.run(directory: Dir.pwd, output_dir: File.join(@output_dir, "after"),
                  server_port: @config.after_port)
      end

      [before_thread.value, after_thread.value]
    end

    def cleanup_branch_sandbox(sandbox, worktree)
      return unless sandbox

      puts "   Cleaning up sandbox databases..."
      sandbox.cleanup(directory: worktree.path, database_url: sandbox.before_url)
      sandbox.cleanup(directory: Dir.pwd, database_url: sandbox.after_url)
    end

    def run_branch_without_servers(worktree)
      puts "3. Running smoke tests (before)..."
      smoke = SmokeTest.new(@identifier)
      before_result = smoke.run(directory: worktree.path, output_dir: File.join(@output_dir, "before"))

      puts "4. Running smoke tests (after)..."
      after_result = smoke.run(directory: Dir.pwd, output_dir: File.join(@output_dir, "after"))

      [before_result, after_result]
    end

    def generate_lock_diff(before_dir, after_dir)
      before_lock = File.join(before_dir, "Gemfile.lock")
      after_lock = File.join(after_dir, "Gemfile.lock")

      diff, = Open3.capture3("diff", "-u", before_lock, after_lock)
      File.write(File.join(@output_dir, "gemfile_lock.diff"), diff)
    end

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
        sandbox = Sandbox.new(@identifier, config: @config, log_dir: File.join(@output_dir, "sandbox"))
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
      smoke = SmokeTest.new(@identifier)

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
      smoke = SmokeTest.new(@identifier)
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

    def cleanup(*worktrees)
      worktrees.each(&:remove)
    end
  end
end
