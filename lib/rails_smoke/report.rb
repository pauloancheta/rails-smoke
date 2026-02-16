# frozen_string_literal: true

module RailsSmoke
  class Report
    include DiffHelpers

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
      lines << "rails-smoke report: #{@gem_name}"
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

      smoke_diffs = smoke_output_diffs
      smoke_diffs.each do |name, diff_output|
        lines << "## #{name} Diff"
        lines << if diff_output.empty?
                   "  (no differences)"
                 else
                   diff_output
                 end
        lines << ""
      end

      lock_diff = gemfile_lock_diff
      if lock_diff
        lines << "## Gemfile.lock Diff"
        lines << if lock_diff.empty?
                   "  (no changes)"
                 else
                   lock_diff
                 end
      end

      lines << ""
      lines << "Artifacts saved to: #{@output_dir}"
      lines.join("\n")
    end
  end
end
