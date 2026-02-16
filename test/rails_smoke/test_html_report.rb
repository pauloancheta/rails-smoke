# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class RailsSmoke::TestHtmlReport < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("rails-smoke-html-test")
    FileUtils.mkdir_p(File.join(@tmpdir, "before"))
    FileUtils.mkdir_p(File.join(@tmpdir, "after"))
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_generates_html_file
    report = build_report
    report.generate

    assert File.exist?(File.join(@tmpdir, "report.html"))
  end

  def test_contains_timing_data
    report = build_report(before_opts: { elapsed: 1.234 }, after_opts: { elapsed: 2.567 })
    report.generate

    html = File.read(File.join(@tmpdir, "report.html"))
    assert_includes html, "1.234s"
    assert_includes html, "2.567s"
  end

  def test_contains_exit_status
    report = build_report(after_opts: { success: false })
    report.generate

    html = File.read(File.join(@tmpdir, "report.html"))
    assert_includes html, "badge-pass"
    assert_includes html, "badge-fail"
    assert_includes html, "Before: PASS"
    assert_includes html, "After: FAIL"
  end

  def test_contains_diff_content
    File.write(File.join(@tmpdir, "before", "stdout.log"), "hello\n")
    File.write(File.join(@tmpdir, "after", "stdout.log"), "hello world\n")

    report = build_report(before_opts: { stdout: "hello\n" }, after_opts: { stdout: "hello world\n" })
    report.generate

    html = File.read(File.join(@tmpdir, "report.html"))
    assert_includes html, "diff-add"
    assert_includes html, "diff-del"
  end

  def test_handles_no_differences
    report = build_report(before_opts: { stdout: "same" }, after_opts: { stdout: "same" })
    report.generate

    html = File.read(File.join(@tmpdir, "report.html"))
    assert_includes html, "(no differences)"
  end

  private

  def build_report(before_opts: {}, after_opts: {})
    before_defaults = { stdout: "out", stderr: "err", elapsed: 1.0, success: true }
    after_defaults = { stdout: "out", stderr: "err", elapsed: 1.5, success: true }

    before = RailsSmoke::SmokeTest::Result.new(**before_defaults, **before_opts)
    after = RailsSmoke::SmokeTest::Result.new(**after_defaults, **after_opts)
    RailsSmoke::HtmlReport.new("test-gem", before: before, after: after, output_dir: @tmpdir)
  end
end
