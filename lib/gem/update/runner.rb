# frozen_string_literal: true

require "fileutils"

module Gem
  module Update
    class Runner
      def initialize(gem_name)
        @gem_name = gem_name
        @output_dir = File.join("tmp", "gem_updates", gem_name)
      end

      def run
        setup_output_dir

        puts "== gem-update: #{@gem_name} =="
        puts ""

        puts "1. Creating worktree..."
        worktree = Worktree.new(@gem_name, base_dir: @output_dir)
        worktree.create

        puts "2. Running bundle update #{@gem_name}..."
        updater = GemUpdater.new(@gem_name, worktree_path: worktree.path, output_dir: @output_dir)
        unless updater.run
          warn "bundle update #{@gem_name} failed. Check #{@output_dir}/bundle_update.log"
          cleanup(worktree)
          exit 1
        end

        puts "3. Running smoke tests (before)..."
        smoke = SmokeTest.new(@gem_name)
        before_result = smoke.run(directory: Dir.pwd, output_dir: File.join(@output_dir, "before"))

        puts "4. Running smoke tests (after)..."
        after_result = smoke.run(directory: worktree.path, output_dir: File.join(@output_dir, "after"))

        puts "5. Generating report..."
        report = Report.new(@gem_name, before: before_result, after: after_result, output_dir: @output_dir)
        report.generate

        cleanup(worktree)
      end

      private

      def setup_output_dir
        FileUtils.rm_rf(@output_dir)
        FileUtils.mkdir_p(@output_dir)
      end

      def cleanup(worktree)
        worktree.remove
      end
    end
  end
end
