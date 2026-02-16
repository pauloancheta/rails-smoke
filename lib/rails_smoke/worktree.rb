# frozen_string_literal: true

require "fileutils"
require "open3"

module RailsSmoke
  class Worktree
    attr_reader :path

    def initialize(name, base_dir:, suffix: "worktree")
      @name = name
      @path = File.join(base_dir, suffix)
    end

    def create(ref: "HEAD")
      FileUtils.mkdir_p(File.dirname(@path))
      out, status = Open3.capture2e("git", "worktree", "add", "--detach", "--force", @path, ref)
      return if status.success?

      raise "Failed to create git worktree at #{@path} for ref '#{ref}': #{out.strip}"
    end

    def remove
      system("git", "worktree", "remove", @path, "--force", out: File::NULL, err: File::NULL)
    end
  end
end
