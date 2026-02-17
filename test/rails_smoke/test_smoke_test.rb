# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class RailsSmoke::TestSmokeTest < Minitest::Test
  def setup
    @original_dir = Dir.pwd
    @tmpdir = File.realpath(Dir.mktmpdir("rails-smoke-smoke-test"))
    Dir.chdir(@tmpdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
  end

  def test_discovers_files_in_smoke_directory
    FileUtils.mkdir_p("test/smoke")
    File.write("test/smoke/boot.rb", 'puts "boot"')
    File.write("test/smoke/routes.rb", 'puts "routes"')

    smoke = RailsSmoke::SmokeTest.new("myapp")
    files = smoke.test_files
    assert_includes files, File.join(@tmpdir, "test/smoke/boot.rb")
    assert_includes files, File.join(@tmpdir, "test/smoke/routes.rb")
  end

  def test_discovers_files_in_subdirectories
    FileUtils.mkdir_p("test/smoke/models")
    File.write("test/smoke/boot.rb", 'puts "boot"')
    File.write("test/smoke/models/user.rb", 'puts "user"')

    smoke = RailsSmoke::SmokeTest.new("myapp")
    files = smoke.test_files
    assert_includes files, File.join(@tmpdir, "test/smoke/boot.rb")
    assert_includes files, File.join(@tmpdir, "test/smoke/models/user.rb")
  end

  def test_no_test_files
    smoke = RailsSmoke::SmokeTest.new("myapp")
    assert_empty smoke.test_files
  end

  def test_run_with_no_tests_returns_failure
    output_dir = File.join(@tmpdir, "output")
    smoke = RailsSmoke::SmokeTest.new("myapp")
    result = smoke.run(directory: @tmpdir, output_dir: output_dir)

    refute result.success
    assert_match(/No smoke tests found/, result.stderr)
  end

  def test_run_writes_runtime_config_with_server_port
    FileUtils.mkdir_p("test/smoke")
    File.write("test/smoke/myapp.rb", <<~'RUBY')
      require "yaml"
      config = YAML.safe_load_file(ARGV[0])
      puts "PORT=#{config["server_port"]}"
    RUBY

    File.write("Gemfile", 'source "https://rubygems.org"')
    system("bundle", "install", "--quiet", out: File::NULL, err: File::NULL)

    output_dir = File.join(@tmpdir, "output")
    smoke = RailsSmoke::SmokeTest.new("myapp")
    result = smoke.run(directory: @tmpdir, output_dir: output_dir, server_port: 4000)

    assert_match(/PORT=4000/, result.stdout)
  end

  def test_run_writes_runtime_config_with_output_dir
    FileUtils.mkdir_p("test/smoke")
    File.write("test/smoke/myapp.rb", <<~RUBY)
      require "yaml"
      config = YAML.safe_load_file(ARGV[0])
      File.write(File.join(config["output_dir"], "test.log"), "logged")
    RUBY

    File.write("Gemfile", 'source "https://rubygems.org"')
    system("bundle", "install", "--quiet", out: File::NULL, err: File::NULL)

    output_dir = File.join(@tmpdir, "output")
    smoke = RailsSmoke::SmokeTest.new("myapp")
    smoke.run(directory: @tmpdir, output_dir: output_dir)

    assert File.exist?(File.join(output_dir, "smoke", "test.log"))
    assert_equal "logged", File.read(File.join(output_dir, "smoke", "test.log"))
  end

  def test_run_command_executes_shell_command
    output_dir = File.join(@tmpdir, "output")
    smoke = RailsSmoke::SmokeTest.new("myapp")
    result = smoke.run_command(command: 'echo "hello world"', directory: @tmpdir, output_dir: output_dir)

    assert result.success
    assert_match(/hello world/, result.stdout)
    assert_kind_of Float, result.elapsed
  end

  def test_run_command_writes_artifact_files
    output_dir = File.join(@tmpdir, "output")
    smoke = RailsSmoke::SmokeTest.new("myapp")
    smoke.run_command(command: 'echo "out"; echo "err" >&2', directory: @tmpdir, output_dir: output_dir)

    assert File.exist?(File.join(output_dir, "stdout.log"))
    assert File.exist?(File.join(output_dir, "stderr.log"))
    assert File.exist?(File.join(output_dir, "timing.txt"))
    assert_match(/out/, File.read(File.join(output_dir, "stdout.log")))
    assert_match(/err/, File.read(File.join(output_dir, "stderr.log")))
    assert_match(/\d+\.\d+s/, File.read(File.join(output_dir, "timing.txt")))
  end

  def test_run_command_returns_failure_for_failing_command
    output_dir = File.join(@tmpdir, "output")
    smoke = RailsSmoke::SmokeTest.new("myapp")
    result = smoke.run_command(command: "exit 1", directory: @tmpdir, output_dir: output_dir)

    refute result.success
  end

  def test_run_probes_executes_probe_script_and_writes_output
    # Create a mock probe script in a temp probes dir
    probes_dir = File.join(@tmpdir, "mock_probes")
    FileUtils.mkdir_p(probes_dir)
    File.write(File.join(probes_dir, "boot_and_load.rb"), <<~'RUBY')
      require "yaml"
      config = YAML.safe_load_file(ARGV[0])
      output_dir = config.fetch("output_dir")
      File.write(File.join(output_dir, "probe_boot.txt"), "status: OK\nboot_time: 0.123s\n")
      File.write(File.join(output_dir, "probe_eager_load.txt"), "status: OK\nconstants_count: 42\n")
    RUBY

    File.write("Gemfile", 'source "https://rubygems.org"')
    system("bundle", "install", "--quiet", out: File::NULL, err: File::NULL)

    output_dir = File.join(@tmpdir, "output")
    smoke = RailsSmoke::SmokeTest.new("myapp")

    # Stub probe_scripts to return our mock script
    smoke.define_singleton_method(:probe_scripts) do |_probes|
      [File.join(probes_dir, "boot_and_load.rb")]
    end

    smoke.run_probes(probes: true, directory: @tmpdir, output_dir: output_dir)

    assert File.exist?(File.join(output_dir, "smoke", "probe_boot.txt"))
    assert File.exist?(File.join(output_dir, "smoke", "probe_eager_load.txt"))
    assert_match(/status: OK/, File.read(File.join(output_dir, "smoke", "probe_boot.txt")))
    assert_match(/status: OK/, File.read(File.join(output_dir, "smoke", "probe_eager_load.txt")))
  end

  def test_run_probes_with_true_finds_all_probe_scripts
    smoke = RailsSmoke::SmokeTest.new("myapp")
    scripts = smoke.send(:probe_scripts, true)

    assert_equal 8, scripts.size
    assert scripts.any? { |s| s.end_with?("boot_and_load.rb") }
    assert scripts.any? { |s| s.end_with?("app_internals.rb") }
    assert scripts.any? { |s| s.end_with?("rake_tasks.rb") }
    assert scripts.any? { |s| s.end_with?("routes.rb") }
    assert scripts.any? { |s| s.end_with?("native_gems.rb") }
    assert scripts.any? { |s| s.end_with?("system_deps.rb") }
    assert scripts.any? { |s| s.end_with?("ruby_warnings.rb") }
    assert scripts.any? { |s| s.end_with?("ssl_certs.rb") }
  end

  def test_run_probes_with_array_finds_app_internals
    smoke = RailsSmoke::SmokeTest.new("myapp")
    scripts = smoke.send(:probe_scripts, ["app_internals"])

    assert_equal 1, scripts.size
    assert scripts.first.end_with?("app_internals.rb")
  end

  def test_run_probes_with_array_finds_named_scripts
    smoke = RailsSmoke::SmokeTest.new("myapp")
    scripts = smoke.send(:probe_scripts, ["boot_and_load"])

    assert_equal 1, scripts.size
    assert scripts.first.end_with?("boot_and_load.rb")
  end

  def test_run_probes_with_array_ignores_missing_scripts
    smoke = RailsSmoke::SmokeTest.new("myapp")
    scripts = smoke.send(:probe_scripts, ["nonexistent"])

    assert_empty scripts
  end

  def test_runtime_config_omits_server_port_when_nil
    FileUtils.mkdir_p("test/smoke")
    File.write("test/smoke/myapp.rb", <<~'RUBY')
      require "yaml"
      config = YAML.safe_load_file(ARGV[0])
      puts "has_port=#{config.key?("server_port")}"
    RUBY

    File.write("Gemfile", 'source "https://rubygems.org"')
    system("bundle", "install", "--quiet", out: File::NULL, err: File::NULL)

    output_dir = File.join(@tmpdir, "output")
    smoke = RailsSmoke::SmokeTest.new("myapp")
    result = smoke.run(directory: @tmpdir, output_dir: output_dir)

    assert_match(/has_port=false/, result.stdout)
  end
end
