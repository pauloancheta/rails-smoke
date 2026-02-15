# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class Gem::TestGemUpdater < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("gem-update-updater-test")
    @output_dir = File.join(@tmpdir, "output")
    FileUtils.mkdir_p(@output_dir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_pin_version_replaces_existing_gem_line
    worktree = File.join(@tmpdir, "worktree")
    FileUtils.mkdir_p(worktree)
    File.write(File.join(worktree, "Gemfile"), <<~GEMFILE)
      source "https://rubygems.org"
      gem "rails", "~> 7.1.0"
      gem "pg"
    GEMFILE

    updater = Gem::Update::GemUpdater.new("rails", worktree_path: worktree, output_dir: @output_dir, version: "7.2.0")
    updater.send(:pin_version)

    content = File.read(File.join(worktree, "Gemfile"))
    assert_includes content, 'gem "rails", "7.2.0"'
    refute_includes content, "~> 7.1.0"
  end

  def test_pin_version_appends_when_gem_not_in_gemfile
    worktree = File.join(@tmpdir, "worktree")
    FileUtils.mkdir_p(worktree)
    File.write(File.join(worktree, "Gemfile"), <<~GEMFILE)
      source "https://rubygems.org"
      gem "pg"
    GEMFILE

    updater = Gem::Update::GemUpdater.new("sidekiq", worktree_path: worktree, output_dir: @output_dir, version: "7.0.0")
    updater.send(:pin_version)

    content = File.read(File.join(worktree, "Gemfile"))
    assert_includes content, 'gem "sidekiq", "7.0.0"'
  end

  def test_no_pin_when_version_nil
    worktree = File.join(@tmpdir, "worktree")
    FileUtils.mkdir_p(worktree)
    original = <<~GEMFILE
      source "https://rubygems.org"
      gem "rails", "~> 7.1.0"
    GEMFILE
    File.write(File.join(worktree, "Gemfile"), original)

    Gem::Update::GemUpdater.new("rails", worktree_path: worktree, output_dir: @output_dir)

    content = File.read(File.join(worktree, "Gemfile"))
    assert_equal original, content
  end
end
