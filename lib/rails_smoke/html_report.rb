# frozen_string_literal: true

module RailsSmoke
  class HtmlReport # rubocop:disable Metrics/ClassLength
    include DiffHelpers

    def initialize(gem_name, before:, after:, output_dir:)
      @gem_name = gem_name
      @before = before
      @after = after
      @output_dir = output_dir
    end

    def generate
      html = build_html
      File.write(File.join(@output_dir, "report.html"), html)
    end

    private

    def build_html
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>rails-smoke report: #{escape(@gem_name)}</title>
          <style>#{css}</style>
        </head>
        <body>
          <div class="container">
            #{header_section}
            #{performance_section}
            #{exit_status_section}
            #{diff_sections}
            <footer>Artifacts saved to: #{escape(@output_dir)}</footer>
          </div>
        </body>
        </html>
      HTML
    end

    def header_section
      <<~HTML
        <header>
          <h1>rails-smoke report: #{escape(@gem_name)}</h1>
          <p class="timestamp">Generated at #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}</p>
        </header>
      HTML
    end

    def performance_section
      before_time = @before.elapsed
      after_time = @after.elapsed
      max_time = [before_time, after_time].max
      max_time = 0.001 if max_time.zero?

      before_pct = (before_time / max_time * 100).round(1)
      after_pct = (after_time / max_time * 100).round(1)

      diff = after_time - before_time
      diff_pct = before_time.zero? ? 0.0 : ((diff / before_time) * 100).round(1)
      sign = diff >= 0 ? "+" : ""
      diff_class = diff >= 0 ? "slower" : "faster"

      <<~HTML
        <section>
          <h2>Performance</h2>
          <div class="chart">
            <div class="chart-row">
              <span class="chart-label">Before</span>
              <div class="bar-container">
                <div class="bar bar-before" style="width: #{before_pct}%"></div>
              </div>
              <span class="chart-value">#{format("%.3fs", before_time)}</span>
            </div>
            <div class="chart-row">
              <span class="chart-label">After</span>
              <div class="bar-container">
                <div class="bar bar-after" style="width: #{after_pct}%"></div>
              </div>
              <span class="chart-value">#{format("%.3fs", after_time)}</span>
            </div>
          </div>
          <p class="diff-summary #{diff_class}">
            Difference: #{sign}#{format("%.3fs", diff)} (#{sign}#{diff_pct}%)
          </p>
        </section>
      HTML
    end

    def exit_status_section
      <<~HTML
        <section>
          <h2>Exit Status</h2>
          <div class="badges">
            <span class="badge #{@before.success ? "badge-pass" : "badge-fail"}">
              Before: #{@before.success ? "PASS" : "FAIL"}
            </span>
            <span class="badge #{@after.success ? "badge-pass" : "badge-fail"}">
              After: #{@after.success ? "PASS" : "FAIL"}
            </span>
          </div>
        </section>
      HTML
    end

    def diff_sections
      sections = []

      sections << diff_detail("Stdout Diff", text_diff(@before.stdout, @after.stdout, "stdout"))
      sections << diff_detail("Stderr Diff", text_diff(@before.stderr, @after.stderr, "stderr"))

      smoke_output_diffs.each do |name, diff_output|
        sections << diff_detail("#{escape(name)} Diff", diff_output)
      end

      lock_diff = gemfile_lock_diff
      sections << diff_detail("Gemfile.lock Diff", lock_diff || "") if lock_diff

      sections.join("\n")
    end

    def diff_detail(title, diff_content)
      body = if diff_content.nil? || diff_content.empty?
               '<p class="no-diff">(no differences)</p>'
             else
               "<pre class=\"diff\">#{style_diff(diff_content)}</pre>"
             end

      <<~HTML
        <details>
          <summary>#{title}</summary>
          #{body}
        </details>
      HTML
    end

    def style_diff(diff_text)
      diff_text.each_line.map do |line|
        escaped = escape(line.chomp)
        case line
        when /\A\+/
          "<span class=\"diff-add\">#{escaped}</span>"
        when /\A-/
          "<span class=\"diff-del\">#{escaped}</span>"
        when /\A@@/
          "<span class=\"diff-hunk\">#{escaped}</span>"
        else
          escaped
        end
      end.join("\n")
    end

    def escape(text)
      text.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub('"', "&quot;")
    end

    def css
      <<~CSS
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f5f5f5; color: #333; padding: 2rem; }
        .container { max-width: 900px; margin: 0 auto; }
        header { margin-bottom: 2rem; }
        h1 { font-size: 1.5rem; margin-bottom: 0.25rem; }
        .timestamp { color: #888; font-size: 0.85rem; }
        h2 { font-size: 1.2rem; margin-bottom: 0.75rem; border-bottom: 1px solid #ddd; padding-bottom: 0.25rem; }
        section { background: #fff; border-radius: 8px; padding: 1.25rem; margin-bottom: 1rem; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
        .chart { margin-bottom: 0.75rem; }
        .chart-row { display: flex; align-items: center; margin-bottom: 0.5rem; }
        .chart-label { width: 60px; font-weight: 600; font-size: 0.9rem; }
        .bar-container { flex: 1; background: #eee; border-radius: 4px; height: 24px; margin: 0 0.75rem; overflow: hidden; }
        .bar { height: 100%; border-radius: 4px; transition: width 0.3s; }
        .bar-before { background: #6c9bd2; }
        .bar-after { background: #f0a860; }
        .chart-value { width: 80px; text-align: right; font-size: 0.9rem; font-variant-numeric: tabular-nums; }
        .diff-summary { font-weight: 600; font-size: 0.95rem; }
        .diff-summary.slower { color: #c0392b; }
        .diff-summary.faster { color: #27ae60; }
        .badges { display: flex; gap: 0.75rem; }
        .badge { padding: 0.35rem 1rem; border-radius: 4px; font-weight: 600; font-size: 0.9rem; }
        .badge-pass { background: #d4edda; color: #155724; }
        .badge-fail { background: #f8d7da; color: #721c24; }
        details { background: #fff; border-radius: 8px; padding: 1rem 1.25rem; margin-bottom: 1rem; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
        summary { cursor: pointer; font-weight: 600; font-size: 1.1rem; }
        .diff { background: #fafafa; border: 1px solid #e0e0e0; border-radius: 4px; padding: 0.75rem; font-family: "SFMono-Regular", Consolas, monospace; font-size: 0.82rem; overflow-x: auto; line-height: 1.5; }
        .diff-add { background: #e6ffec; color: #22863a; display: block; }
        .diff-del { background: #ffeef0; color: #b31d28; display: block; }
        .diff-hunk { background: #f1f8ff; color: #005cc5; display: block; }
        .no-diff { color: #888; font-style: italic; padding: 0.5rem 0; }
        footer { color: #888; font-size: 0.85rem; margin-top: 1.5rem; }
      CSS
    end
  end
end
