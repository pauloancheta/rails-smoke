# frozen_string_literal: true

require "open3"

module Gem
  module Update
    class GemUpdater
      def initialize(gem_name, worktree_path:, output_dir:)
        @gem_name = gem_name
        @worktree_path = worktree_path
        @output_dir = output_dir
      end

      def run
        stdout, stderr, status = Open3.capture3(
          "bundle", "update", @gem_name,
          chdir: @worktree_path
        )

        log = "$ bundle update #{@gem_name}\n\n#{stdout}\n#{stderr}"
        File.write(File.join(@output_dir, "bundle_update.log"), log)

        generate_diff

        status.success?
      end

      private

      def generate_diff
        original_lock = File.join(Dir.pwd, "Gemfile.lock")
        updated_lock = File.join(@worktree_path, "Gemfile.lock")

        diff, = Open3.capture3("diff", "-u", original_lock, updated_lock)
        File.write(File.join(@output_dir, "gemfile_lock.diff"), diff)
      end
    end
  end
end
