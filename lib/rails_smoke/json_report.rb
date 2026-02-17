# frozen_string_literal: true

require "json"

module RailsSmoke
  class JsonReport
    include DiffHelpers

    def initialize(gem_name, before:, after:, output_dir:)
      @gem_name = gem_name
      @before = before
      @after = after
      @output_dir = output_dir
    end

    def generate
      path = File.join(@output_dir, "report.json")
      File.write(path, JSON.pretty_generate(build_report))
      path
    end

    private

    def build_report
      {
        version: "1.0",
        identifier: @gem_name,
        generated_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
        result: result_status,
        before: {
          success: @before.success,
          elapsed: @before.elapsed.round(3)
        },
        after: {
          success: @after.success,
          elapsed: @after.elapsed.round(3)
        },
        diffs: build_diffs
      }
    end

    def result_status
      if @after.success && @before.success
        "pass"
      elsif !@after.success && @before.success
        "regression"
      elsif !@after.success && !@before.success
        "baseline_broken"
      else
        "fail"
      end
    end

    def build_diffs
      diffs = {
        stdout: nullable_diff(@before.stdout, @after.stdout, "stdout"),
        stderr: nullable_diff(@before.stderr, @after.stderr, "stderr"),
        gemfile_lock: gemfile_lock_diff.then { |d| d.nil? || d.empty? ? nil : d }
      }

      smoke_diffs = {}
      smoke_output_diffs.each do |name, diff_output|
        key = name.downcase.tr(" ", "_")
        smoke_diffs[key] = diff_output.empty? ? nil : diff_output
      end
      diffs[:smoke_outputs] = smoke_diffs unless smoke_diffs.empty?

      diffs
    end

    def nullable_diff(before_text, after_text, label)
      diff = text_diff(before_text, after_text, label)
      diff.empty? ? nil : diff
    end
  end
end
