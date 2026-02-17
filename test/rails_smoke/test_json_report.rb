# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

class RailsSmoke::TestJsonReport < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("rails-smoke-json-test")
    FileUtils.mkdir_p(File.join(@tmpdir, "before"))
    FileUtils.mkdir_p(File.join(@tmpdir, "after"))
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_generates_json_file
    report = build_report
    report.generate

    assert File.exist?(File.join(@tmpdir, "report.json"))
  end

  def test_contains_timing_data
    report = build_report(before_opts: { elapsed: 1.234 }, after_opts: { elapsed: 2.567 })
    report.generate

    data = parse_report
    assert_equal 1.234, data["before"]["elapsed"]
    assert_equal 2.567, data["after"]["elapsed"]
  end

  def test_contains_exit_status
    report = build_report(before_opts: { success: true }, after_opts: { success: false })
    report.generate

    data = parse_report
    assert_equal true, data["before"]["success"]
    assert_equal false, data["after"]["success"]
  end

  def test_result_pass_when_both_succeed
    report = build_report(before_opts: { success: true }, after_opts: { success: true })
    report.generate

    data = parse_report
    assert_equal "pass", data["result"]
  end

  def test_result_fail_when_after_fails
    report = build_report(before_opts: { success: false }, after_opts: { success: false })
    report.generate

    data = parse_report
    assert_includes ["fail", "regression", "baseline_broken"], data["result"]
  end

  def test_result_regression_when_before_pass_after_fail
    report = build_report(before_opts: { success: true }, after_opts: { success: false })
    report.generate

    data = parse_report
    assert_equal "regression", data["result"]
  end

  def test_result_baseline_broken_when_both_fail
    report = build_report(before_opts: { success: false }, after_opts: { success: false })
    report.generate

    data = parse_report
    assert_equal "baseline_broken", data["result"]
  end

  def test_contains_diffs
    File.write(File.join(@tmpdir, "before", "stdout.log"), "hello\n")
    File.write(File.join(@tmpdir, "after", "stdout.log"), "hello world\n")

    report = build_report(before_opts: { stdout: "hello\n" }, after_opts: { stdout: "hello world\n" })
    report.generate

    data = parse_report
    refute_nil data["diffs"]["stdout"]
  end

  def test_null_diffs_when_no_differences
    report = build_report(before_opts: { stdout: "same" }, after_opts: { stdout: "same" })
    report.generate

    data = parse_report
    assert_nil data["diffs"]["stdout"]
  end

  def test_contains_version_and_identifier
    report = build_report
    report.generate

    data = parse_report
    assert_equal "1.0", data["version"]
    assert_equal "test-gem", data["identifier"]
    assert data.key?("generated_at")
  end

  private

  def build_report(before_opts: {}, after_opts: {})
    before_defaults = { stdout: "out", stderr: "err", elapsed: 1.0, success: true }
    after_defaults = { stdout: "out", stderr: "err", elapsed: 1.5, success: true }

    before = RailsSmoke::SmokeTest::Result.new(**before_defaults, **before_opts)
    after = RailsSmoke::SmokeTest::Result.new(**after_defaults, **after_opts)
    RailsSmoke::JsonReport.new("test-gem", before: before, after: after, output_dir: @tmpdir)
  end

  def parse_report
    JSON.parse(File.read(File.join(@tmpdir, "report.json")))
  end
end
