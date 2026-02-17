# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class RailsSmoke::TestConfig < Minitest::Test # rubocop:disable Metrics/ClassLength
  def setup
    @tmpdir = Dir.mktmpdir("rails-smoke-config-test")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_raises_when_no_config_file
    error = assert_raises(RailsSmoke::Error) do
      RailsSmoke::Config.new(project_root: @tmpdir)
    end

    assert_match(/Config file not found/, error.message)
  end

  def test_raises_when_gem_name_missing
    write_config("server" => true)

    error = assert_raises(RailsSmoke::Error) do
      RailsSmoke::Config.new(project_root: @tmpdir)
    end

    assert_match(/gem_name is required/, error.message)
  end

  def test_raises_when_gem_name_empty
    write_config("gem_name" => "  ")

    error = assert_raises(RailsSmoke::Error) do
      RailsSmoke::Config.new(project_root: @tmpdir)
    end

    assert_match(/gem_name is required/, error.message)
  end

  def test_reads_gem_name
    write_config("gem_name" => "rails")

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_equal "rails", config.gem_name
  end

  def test_defaults_with_minimal_config
    write_config("gem_name" => "rails")

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    refute config.server?
    assert_equal 3000, config.before_port
    assert_equal 3001, config.after_port
    assert_equal "test", config.rails_env
    assert config.sandbox?
    assert_nil config.version
    assert_nil config.setup_task
    assert_nil config.setup_script
    assert_nil config.database_url_base
    assert_nil config.test_command
  end

  def test_test_command_can_be_set
    write_config("gem_name" => "rails", "test_command" => "bundle exec rspec")

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_equal "bundle exec rspec", config.test_command
  end

  def test_overrides_defaults
    write_config(
      "gem_name" => "rails",
      "server" => true,
      "before_port" => 5000,
      "after_port" => 5001,
      "version" => "7.2.0",
      "sandbox" => false,
      "rails_env" => "staging",
      "setup_task" => "db:seed",
      "setup_script" => "test/smoke/seed.rb",
      "database_url_base" => "postgresql://localhost"
    )

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert config.server?
    assert_equal 5000, config.before_port
    assert_equal 5001, config.after_port
    assert_equal "7.2.0", config.version
    refute config.sandbox?
    assert_equal "staging", config.rails_env
    assert_equal "db:seed", config.setup_task
    assert_equal "test/smoke/seed.rb", config.setup_script
    assert_equal "postgresql://localhost", config.database_url_base
  end

  def test_empty_yaml_file_raises
    File.write(File.join(@tmpdir, ".rails_smoke.yml"), "")

    error = assert_raises(RailsSmoke::Error) do
      RailsSmoke::Config.new(project_root: @tmpdir)
    end

    assert_match(/gem_name is required/, error.message)
  end

  # --- Gem mode ---

  def test_gem_mode_detection
    write_config("gem_name" => "rails")

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_equal "gem", config.mode
  end

  def test_gem_mode_identifier
    write_config("gem_name" => "rails")

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_equal "rails", config.identifier
  end

  # --- Branch mode ---

  def test_branch_mode_with_both_branches
    write_config("before_branch" => "main", "after_branch" => "bump-rack-3.0")

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_equal "branch", config.mode
    assert_equal "main", config.before_branch
    assert_equal "bump-rack-3.0", config.after_branch
  end

  def test_branch_mode_identifier_is_after_branch
    write_config("before_branch" => "main", "after_branch" => "bump-rack-3.0")

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_equal "bump-rack-3.0", config.identifier
  end

  def test_branch_mode_defaults_before_branch_to_main
    write_config("after_branch" => "bump-rack-3.0")

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_equal "branch", config.mode
    assert_equal "main", config.before_branch
    assert_equal "bump-rack-3.0", config.after_branch
  end

  def test_branch_mode_defaults_after_branch_to_current_branch
    write_config("before_branch" => "main")

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_equal "branch", config.mode
    assert_equal "main", config.before_branch
    # after_branch defaults to current git branch
    refute_nil config.after_branch
    refute_empty config.after_branch
  end

  def test_branch_mode_no_gem_name
    write_config("before_branch" => "main", "after_branch" => "bump-rack-3.0")

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_nil config.gem_name
  end

  # --- database_url_base auto-detection ---

  def test_auto_detects_database_url_base_from_database_yml
    write_config("gem_name" => "rails")
    write_database_yml(
      "test" => {
        "adapter" => "postgresql",
        "host" => "localhost",
        "port" => 5432,
        "username" => "myapp",
        "password" => "secret"
      }
    )

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_equal "postgresql://myapp:secret@localhost:5432", config.database_url_base
  end

  def test_auto_detects_database_url_base_without_password
    write_config("gem_name" => "rails")
    write_database_yml(
      "test" => {
        "adapter" => "postgresql",
        "host" => "localhost",
        "username" => "myapp"
      }
    )

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_equal "postgresql://myapp@localhost", config.database_url_base
  end

  def test_auto_detects_mysql2_database_url_base
    write_config("gem_name" => "rails")
    write_database_yml(
      "test" => {
        "adapter" => "mysql2",
        "host" => "127.0.0.1",
        "port" => 3306,
        "username" => "root"
      }
    )

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_equal "mysql2://root@127.0.0.1:3306", config.database_url_base
  end

  def test_auto_detects_sqlite3_database_url_base
    write_config("gem_name" => "rails")
    write_database_yml(
      "test" => {
        "adapter" => "sqlite3",
        "database" => "db/test.sqlite3"
      }
    )

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_equal "sqlite3", config.database_url_base
  end

  def test_explicit_database_url_base_overrides_auto_detection
    write_config("gem_name" => "rails", "database_url_base" => "postgresql://custom:5433")
    write_database_yml(
      "test" => {
        "adapter" => "postgresql",
        "host" => "localhost",
        "username" => "myapp"
      }
    )

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_equal "postgresql://custom:5433", config.database_url_base
  end

  def test_auto_detect_returns_nil_without_database_yml
    write_config("gem_name" => "rails")

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_nil config.database_url_base
  end

  def test_auto_detect_uses_configured_rails_env
    write_config("gem_name" => "rails", "rails_env" => "development")
    write_database_yml(
      "development" => {
        "adapter" => "postgresql",
        "host" => "devhost",
        "username" => "devuser"
      },
      "test" => {
        "adapter" => "sqlite3",
        "database" => "db/test.sqlite3"
      }
    )

    config = RailsSmoke::Config.new(project_root: @tmpdir)

    assert_equal "postgresql://devuser@devhost", config.database_url_base
  end

  def test_raises_when_both_gem_name_and_branch_fields
    write_config("gem_name" => "rails", "after_branch" => "bump-rack-3.0")

    error = assert_raises(RailsSmoke::Error) do
      RailsSmoke::Config.new(project_root: @tmpdir)
    end

    assert_match(/Cannot set both gem_name and branch fields/, error.message)
  end

  def test_raises_when_gem_name_and_before_branch
    write_config("gem_name" => "rails", "before_branch" => "develop")

    error = assert_raises(RailsSmoke::Error) do
      RailsSmoke::Config.new(project_root: @tmpdir)
    end

    assert_match(/Cannot set both gem_name and branch fields/, error.message)
  end

  private

  def write_config(hash)
    File.write(File.join(@tmpdir, ".rails_smoke.yml"), YAML.dump(hash))
  end

  def write_database_yml(hash)
    config_dir = File.join(@tmpdir, "config")
    FileUtils.mkdir_p(config_dir)
    File.write(File.join(config_dir, "database.yml"), YAML.dump(hash))
  end
end
