# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class Gem::TestWorktree < Minitest::Test
  def setup
    @original_dir = Dir.pwd
    @tmpdir = Dir.mktmpdir("gem-update-test")
    Dir.chdir(@tmpdir)
    system("git", "init", out: File::NULL, err: File::NULL)
    system("git", "config", "user.email", "test@test.com", out: File::NULL, err: File::NULL)
    system("git", "config", "user.name", "Test", out: File::NULL, err: File::NULL)
    File.write("dummy.txt", "hello")
    system("git", "add", ".", out: File::NULL, err: File::NULL)
    system("git", "commit", "-m", "init", out: File::NULL, err: File::NULL)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
  end

  def test_create_and_remove_worktree
    base_dir = File.join(@tmpdir, "output")
    worktree = Gem::Update::Worktree.new("test-gem", base_dir: base_dir)

    assert worktree.create
    assert File.directory?(worktree.path)
    assert File.exist?(File.join(worktree.path, "dummy.txt"))

    worktree.remove
    refute File.directory?(worktree.path)
  end

  def test_path
    worktree = Gem::Update::Worktree.new("rails", base_dir: "/tmp/gem_updates/rails")
    assert_equal "/tmp/gem_updates/rails/worktree", worktree.path
  end
end
