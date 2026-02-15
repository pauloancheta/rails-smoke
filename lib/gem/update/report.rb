# frozen_string_literal: true

require "open3"

module Gem
  module Update
    class Report
      def initialize(gem_name, before:, after:, output_dir:)
        @gem_name = gem_name
        @before = before
        @after = after
        @output_dir = output_dir
      end

      def generate
        report = build_report
        File.write(File.join(@output_dir, "report.txt"), report)
        puts report
      end

      private

      def build_report
        lines = []
        lines << ("=" * 60)
        lines << "gem-update report: #{@gem_name}"
        lines << ("=" * 60)
        lines << ""
        lines << "## Timing"
        lines << format("  Before: %.3fs", @before.elapsed)
        lines << format("  After:  %.3fs", @after.elapsed)
        diff = @after.elapsed - @before.elapsed
        sign = diff >= 0 ? "+" : ""
        lines << "  Diff:   #{sign}#{format("%.3fs", diff)}"
        lines << ""
        lines << "## Exit Status"
        lines << "  Before: #{@before.success ? "OK" : "FAILED"}"
        lines << "  After:  #{@after.success ? "OK" : "FAILED"}"
        lines << ""

        stdout_diff = text_diff(@before.stdout, @after.stdout, "stdout")
        lines << "## Stdout Diff"
        lines << if stdout_diff.empty?
                   "  (no differences)"
                 else
                   stdout_diff
                 end
        lines << ""

        stderr_diff = text_diff(@before.stderr, @after.stderr, "stderr")
        lines << "## Stderr Diff"
        lines << if stderr_diff.empty?
                   "  (no differences)"
                 else
                   stderr_diff
                 end
        lines << ""

        diff_file = File.join(@output_dir, "gemfile_lock.diff")
        if File.exist?(diff_file)
          content = File.read(diff_file)
          lines << "## Gemfile.lock Diff"
          lines << if content.empty?
                     "  (no changes)"
                   else
                     content
                   end
        end

        lines << ""
        lines << "Artifacts saved to: #{@output_dir}"
        lines.join("\n")
      end

      def text_diff(before_text, after_text, label)
        return "" if before_text == after_text

        before_file = File.join(@output_dir, "before", "#{label}.log")
        after_file = File.join(@output_dir, "after", "#{label}.log")

        diff, = Open3.capture3("diff", "-u", before_file, after_file)
        diff
      end
    end
  end
end
