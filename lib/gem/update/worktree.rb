# frozen_string_literal: true

require "fileutils"

module Gem
  module Update
    class Worktree
      attr_reader :path

      def initialize(gem_name, base_dir:)
        @gem_name = gem_name
        @path = File.join(base_dir, "worktree")
      end

      def create
        FileUtils.mkdir_p(File.dirname(@path))
        system("git", "worktree", "add", @path, "HEAD", out: File::NULL, err: File::NULL)
      end

      def remove
        system("git", "worktree", "remove", @path, "--force", out: File::NULL, err: File::NULL)
      end
    end
  end
end
