# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class Gem::TestSmokeTest < Minitest::Test
  def setup
    @original_dir = Dir.pwd
    @tmpdir = Dir.mktmpdir("gem-update-smoke-test")
    Dir.chdir(@tmpdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
  end

  def test_discovers_single_file
    FileUtils.mkdir_p("test/smoke")
    File.write("test/smoke/rails.rb", 'puts "hello"')

    smoke = Gem::Update::SmokeTest.new("rails")
    assert_equal ["test/smoke/rails.rb"], smoke.test_files
  end

  def test_discovers_directory_files
    FileUtils.mkdir_p("test/smoke/rails")
    File.write("test/smoke/rails/boot.rb", 'puts "boot"')
    File.write("test/smoke/rails/routes.rb", 'puts "routes"')

    smoke = Gem::Update::SmokeTest.new("rails")
    files = smoke.test_files
    assert_includes files, "test/smoke/rails/boot.rb"
    assert_includes files, "test/smoke/rails/routes.rb"
  end

  def test_discovers_both_single_and_directory
    FileUtils.mkdir_p("test/smoke/rails")
    File.write("test/smoke/rails.rb", 'puts "main"')
    File.write("test/smoke/rails/extra.rb", 'puts "extra"')

    smoke = Gem::Update::SmokeTest.new("rails")
    assert_equal 2, smoke.test_files.size
  end

  def test_no_test_files
    smoke = Gem::Update::SmokeTest.new("nonexistent")
    assert_empty smoke.test_files
  end

  def test_run_with_no_tests_returns_failure
    output_dir = File.join(@tmpdir, "output")
    smoke = Gem::Update::SmokeTest.new("nonexistent")
    result = smoke.run(directory: @tmpdir, output_dir: output_dir)

    refute result.success
    assert_match(/No smoke tests found/, result.stderr)
  end
end
