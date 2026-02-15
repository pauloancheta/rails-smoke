# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class Gem::TestSandbox < Minitest::Test # rubocop:disable Metrics/ClassLength
  def setup
    @tmpdir = Dir.mktmpdir("gem-update-sandbox-test")
    @log_dir = File.join(@tmpdir, "logs")
    @config = build_config
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_generates_unique_db_names
    sandbox = Gem::Update::Sandbox.new("rails", config: @config, log_dir: @log_dir)

    assert_match(/gem_update_rails_before_#{Process.pid}/, sandbox.before_url)
    assert_match(/gem_update_rails_after_#{Process.pid}/, sandbox.after_url)
  end

  def test_builds_database_urls_from_base
    sandbox = Gem::Update::Sandbox.new("rails", config: @config, log_dir: @log_dir)

    assert_equal "postgresql://localhost/gem_update_rails_before_#{Process.pid}", sandbox.before_url
    assert_equal "postgresql://localhost/gem_update_rails_after_#{Process.pid}", sandbox.after_url
  end

  def test_setup_runs_db_create_and_schema_load
    sandbox = Gem::Update::Sandbox.new("rails", config: @config, log_dir: @log_dir)
    commands_run = []

    capture3_stub = lambda do |env, *cmd, **_opts|
      commands_run << { env: env, cmd: cmd }
      ["", "", stub_success_status]
    end

    stub_sandbox(capture3_stub) { sandbox.setup(directory: @tmpdir, database_url: sandbox.before_url) }

    assert_equal 2, commands_run.size
    assert_equal %w[bundle exec rails db:create], commands_run[0][:cmd]
    assert_equal %w[bundle exec rails db:schema:load], commands_run[1][:cmd]

    commands_run.each do |run|
      assert_equal "test", run[:env]["RAILS_ENV"]
      assert_equal "test", run[:env]["RACK_ENV"]
      assert_equal sandbox.before_url, run[:env]["DATABASE_URL"]
    end
  end

  def test_setup_runs_setup_task_when_configured
    config = build_config(setup_task: "db:seed")
    sandbox = Gem::Update::Sandbox.new("rails", config: config, log_dir: @log_dir)
    commands_run = []

    capture3_stub = lambda do |_env, *cmd, **_opts|
      commands_run << { cmd: cmd }
      ["", "", stub_success_status]
    end

    stub_sandbox(capture3_stub) { sandbox.setup(directory: @tmpdir, database_url: sandbox.before_url) }

    assert_equal 3, commands_run.size
    assert_equal %w[bundle exec rails db:seed], commands_run[2][:cmd]
  end

  def test_setup_runs_setup_script_when_configured
    config = build_config(setup_script: "test/smoke/seed.rb")
    sandbox = Gem::Update::Sandbox.new("rails", config: config, log_dir: @log_dir)
    commands_run = []

    capture3_stub = lambda do |_env, *cmd, **_opts|
      commands_run << { cmd: cmd }
      ["", "", stub_success_status]
    end

    stub_sandbox(capture3_stub) { sandbox.setup(directory: @tmpdir, database_url: sandbox.before_url) }

    assert_equal 3, commands_run.size
    assert_equal ["bundle", "exec", "ruby", "test/smoke/seed.rb"], commands_run[2][:cmd]
  end

  def test_setup_runs_both_task_and_script
    config = build_config(setup_task: "db:seed", setup_script: "test/smoke/seed.rb")
    sandbox = Gem::Update::Sandbox.new("rails", config: config, log_dir: @log_dir)
    commands_run = []

    capture3_stub = lambda do |_env, *cmd, **_opts|
      commands_run << { cmd: cmd }
      ["", "", stub_success_status]
    end

    stub_sandbox(capture3_stub) { sandbox.setup(directory: @tmpdir, database_url: sandbox.before_url) }

    assert_equal 4, commands_run.size
    assert_equal %w[bundle exec rails db:create], commands_run[0][:cmd]
    assert_equal %w[bundle exec rails db:schema:load], commands_run[1][:cmd]
    assert_equal %w[bundle exec rails db:seed], commands_run[2][:cmd]
    assert_equal ["bundle", "exec", "ruby", "test/smoke/seed.rb"], commands_run[3][:cmd]
  end

  def test_cleanup_runs_db_drop
    sandbox = Gem::Update::Sandbox.new("rails", config: @config, log_dir: @log_dir)
    commands_run = []

    capture3_stub = lambda do |env, *cmd, **_opts|
      commands_run << { env: env, cmd: cmd }
      ["", "", stub_success_status]
    end

    stub_sandbox(capture3_stub) { sandbox.cleanup(directory: @tmpdir, database_url: sandbox.before_url) }

    assert_equal 1, commands_run.size
    assert_equal %w[bundle exec rails db:drop], commands_run[0][:cmd]
    assert_equal "1", commands_run[0][:env]["DISABLE_DATABASE_ENVIRONMENT_CHECK"]
    assert_equal sandbox.before_url, commands_run[0][:env]["DATABASE_URL"]
  end

  def test_setup_raises_on_command_failure
    sandbox = Gem::Update::Sandbox.new("rails", config: @config, log_dir: @log_dir)

    capture3_stub = lambda do |_env, *_cmd, **_opts|
      ["", "error output", stub_failure_status]
    end

    assert_raises(RuntimeError, /Sandbox command failed/) do
      stub_sandbox(capture3_stub) { sandbox.setup(directory: @tmpdir, database_url: sandbox.before_url) }
    end
  end

  def test_setup_logs_output
    sandbox = Gem::Update::Sandbox.new("rails", config: @config, log_dir: @log_dir)

    capture3_stub = lambda do |_env, *_cmd, **_opts|
      ["stdout content", "stderr content", stub_success_status]
    end

    stub_sandbox(capture3_stub) { sandbox.setup(directory: @tmpdir, database_url: sandbox.before_url) }

    assert File.exist?(File.join(@log_dir, "db_create_stdout.log"))
    assert File.exist?(File.join(@log_dir, "db_create_stderr.log"))
    assert_equal "stdout content", File.read(File.join(@log_dir, "db_create_stdout.log"))
  end

  private

  def stub_sandbox(capture3_stub, &block)
    Open3.stub(:capture3, capture3_stub) do
      Bundler.stub(:with_unbundled_env, ->(&b) { b.call }, &block)
    end
  end

  def build_config(setup_task: nil, setup_script: nil)
    stub = Object.new
    stub.define_singleton_method(:gem_name) { "rails" }
    stub.define_singleton_method(:rails_env) { "test" }
    stub.define_singleton_method(:database_url_base) { "postgresql://localhost" }
    stub.define_singleton_method(:setup_task) { setup_task }
    stub.define_singleton_method(:setup_script) { setup_script }
    stub
  end

  def stub_success_status
    status = Minitest::Mock.new
    status.expect(:success?, true)
    status
  end

  def stub_failure_status
    status = Minitest::Mock.new
    status.expect(:success?, false)
    status.expect(:exitstatus, 1)
    status
  end
end
