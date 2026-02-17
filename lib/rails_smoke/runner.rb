# frozen_string_literal: true

require "fileutils"
require "open3"

module RailsSmoke
  class Runner # rubocop:disable Metrics/ClassLength
    def initialize(config:)
      @config = config
      @identifier = config.identifier
      @worktree_dir = File.join("tmp", "rails_smoke", @identifier)
      @artifacts_dir = "rails_smoke_artifacts"
    end

    def run
      setup_dirs

      puts "== rails-smoke: #{@identifier} =="
      puts ""

      if @config.mode == "branch"
        run_branch_mode
      else
        run_gem_mode
      end
    end

    def success?
      @success
    end

    private

    def run_gem_mode
      puts "1. Creating worktree..."
      worktree = Worktree.new(@identifier, base_dir: @worktree_dir)
      worktree.create

      version_label = @config.version ? " to #{@config.version}" : ""
      puts "2. Running bundle update #{@identifier}#{version_label}..."
      updater = GemUpdater.new(@identifier, worktree_path: worktree.path, output_dir: @artifacts_dir,
                                            version: @config.version)
      unless updater.run
        warn "bundle update #{@identifier} failed. Check #{@artifacts_dir}/bundle_update.log"
        exit 1
      end

      before_result, after_result = if @config.server?
                                      run_with_servers(worktree)
                                    else
                                      run_without_servers(worktree)
                                    end

      @success = generate_reports(before_result, after_result)
    ensure
      cleanup(worktree) if worktree
    end

    def run_branch_mode
      puts "1. Creating worktree for #{@config.before_branch}..."
      worktree = Worktree.new(@identifier, base_dir: @worktree_dir, suffix: "before_worktree")
      worktree.create(ref: @config.before_branch)

      puts "2. Running bundle install in worktree..."
      bundle_install(worktree.path)

      puts "3. Generating Gemfile.lock diff..."
      generate_lock_diff(worktree.path, Dir.pwd)

      before_result, after_result = if @config.server?
                                      run_branch_with_servers(worktree)
                                    else
                                      run_branch_without_servers(worktree)
                                    end

      @success = generate_reports(before_result, after_result)
    ensure
      cleanup(worktree) if worktree
    end

    def run_branch_with_servers(worktree)
      sandbox, before_env, after_env = setup_branch_sandbox(worktree)

      before_server = PumaServer.new(port: @config.before_port, log_dir: File.join(@artifacts_dir, "before"),
                                     env: before_env)
      after_server = PumaServer.new(port: @config.after_port, log_dir: File.join(@artifacts_dir, "after"),
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
        sandbox = Sandbox.new(@identifier, config: @config, log_dir: File.join(@artifacts_dir, "sandbox"))
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
        run_smoke(smoke, directory: worktree.path, output_dir: File.join(@artifacts_dir, "before"),
                  server_port: @config.before_port)
      end
      after_thread = Thread.new do
        run_smoke(smoke, directory: Dir.pwd, output_dir: File.join(@artifacts_dir, "after"),
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
      puts "4. Running smoke tests (before)..."
      smoke = SmokeTest.new(@identifier)
      before_result = run_smoke(smoke, directory: worktree.path, output_dir: File.join(@artifacts_dir, "before"))

      puts "5. Running smoke tests (after)..."
      after_result = run_smoke(smoke, directory: Dir.pwd, output_dir: File.join(@artifacts_dir, "after"))

      [before_result, after_result]
    end

    def generate_reports(before_result, after_result)
      report = Report.new(@identifier, before: before_result, after: after_result, output_dir: @artifacts_dir)
      report_path = report.generate
      html_report = HtmlReport.new(@identifier, before: before_result, after: after_result, output_dir: @artifacts_dir)
      html_path = html_report.generate
      json_report = JsonReport.new(@identifier, before: before_result, after: after_result, output_dir: @artifacts_dir)
      json_path = json_report.generate

      puts ""
      puts "== Done! =="
      puts ""
      puts "  View text report:  cat #{report_path}"
      puts "  View HTML report:  open #{html_path}"
      puts "  View JSON report:  cat #{json_path}"
      puts ""

      after_result.success
    end

    def bundle_install(directory)
      stdout, stderr, status = Bundler.with_unbundled_env do
        Open3.capture3("bundle", "install", chdir: directory)
      end

      log = "$ bundle install\n\n#{stdout}\n#{stderr}"
      File.write(File.join(@artifacts_dir, "bundle_install.log"), log)

      return if status.success?

      warn "bundle install failed in worktree. Check #{@artifacts_dir}/bundle_install.log"
      exit 1
    end

    def generate_lock_diff(before_dir, after_dir)
      before_lock = File.join(before_dir, "Gemfile.lock")
      after_lock = File.join(after_dir, "Gemfile.lock")

      diff, = Open3.capture3("diff", "-u", before_lock, after_lock)
      File.write(File.join(@artifacts_dir, "gemfile_lock.diff"), diff)
    end

    def run_with_servers(worktree)
      sandbox, before_env, after_env = setup_sandbox(worktree)

      before_server = PumaServer.new(port: @config.before_port, log_dir: File.join(@artifacts_dir, "before"),
                                     env: before_env)
      after_server = PumaServer.new(port: @config.after_port, log_dir: File.join(@artifacts_dir, "after"),
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
        sandbox = Sandbox.new(@identifier, config: @config, log_dir: File.join(@artifacts_dir, "sandbox"))
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
        run_smoke(smoke, directory: Dir.pwd, output_dir: File.join(@artifacts_dir, "before"),
                  server_port: @config.before_port)
      end
      after_thread = Thread.new do
        run_smoke(smoke, directory: worktree.path, output_dir: File.join(@artifacts_dir, "after"),
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
      before_result = run_smoke(smoke, directory: Dir.pwd, output_dir: File.join(@artifacts_dir, "before"))

      puts "4. Running smoke tests (after)..."
      after_result = run_smoke(smoke, directory: worktree.path, output_dir: File.join(@artifacts_dir, "after"))

      [before_result, after_result]
    end

    def run_smoke(smoke, directory:, output_dir:, server_port: nil)
      result = if @config.test_command
                 smoke.run_command(command: @config.test_command, directory: directory, output_dir: output_dir)
               else
                 smoke.run(directory: directory, output_dir: output_dir, server_port: server_port)
               end

      if @config.probes
        smoke.run_probes(probes: @config.probes, directory: directory, output_dir: output_dir)
      end

      result
    end

    def setup_dirs
      PumaServer.cleanup_stale(@artifacts_dir) if File.directory?(@artifacts_dir)
      FileUtils.rm_rf(@artifacts_dir)
      FileUtils.mkdir_p(@artifacts_dir)
      FileUtils.mkdir_p(@worktree_dir)
    end

    def shutdown_servers(servers)
      servers.each(&:stop)
    end

    def cleanup(*worktrees)
      worktrees.each(&:remove)
    end
  end
end
