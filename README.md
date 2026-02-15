# gem-update

A/B smoke test gem upgrades using git worktrees. Creates a worktree with an updated gem, runs your smoke tests against both versions, and produces a comparison report with diffs and performance data.

## Installation

```sh
gem install gem-update
```

Or add to your Gemfile:

```ruby
gem "gem-update"
```

## Usage

Run from inside a git repository:

```sh
gem-update <gem_name>
```

### What it does

1. Creates a git worktree from the current HEAD
2. Runs `bundle update <gem_name>` in the worktree
3. Runs your smoke tests against the original and updated code
4. Generates a comparison report (timing, exit status, stdout/stderr diffs, Gemfile.lock diff)
5. Cleans up the worktree

### Writing smoke tests

Place test files at either location:

```
test/smoke/<gem_name>.rb
test/smoke/<gem_name>/*.rb
```

For example, to test a `rails` upgrade:

```ruby
# test/smoke/rails.rb
require "yaml"
require "net/http"

config = YAML.safe_load_file(ARGV[0])
port = config.fetch("server_port")

res = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/health"))
abort "Health check failed: #{res.code}" unless res.code == "200"

puts "Health check passed"
```

Smoke tests run via `bundle exec ruby <file> <config_path>` and receive a runtime YAML config as `ARGV[0]`. They should exit 0 on success and non-zero on failure.

## A/B server testing

For gems that affect a running Rails app (e.g. `rails`, `puma`, `rack`), you can start puma servers against both versions and run smoke tests that make HTTP requests.

### Configuration

Create a `.gem_update.yml` in your project root:

```yaml
defaults:
  server: false
  before_port: 3000
  after_port: 3001

rails:
  server: true
  version: "7.2.0"
  before_port: 4000
  after_port: 4001
```

- **`defaults`** — global settings applied to all gems
- **`<gem_name>`** — per-gem overrides, merged on top of defaults

| Key | Default | Description |
|---|---|---|
| `server` | `false` | Start puma servers for A/B testing |
| `version` | *(latest)* | Target version to update to (e.g. `"7.2.0"`) |
| `before_port` | `3000` | Port for the original (pre-update) server |
| `after_port` | `3001` | Port for the updated (post-update) server |

When `version` is set, the Gemfile in the worktree is pinned to that exact version before running `bundle update`. The before server always runs the current version while the after server runs the specified version. Without `version`, `bundle update` resolves to the latest allowed by your Gemfile constraints.

### How it works

When `server: true` is set for a gem:

1. A puma server starts on the original code at `before_port`
2. A puma server starts on the worktree (updated code) at `after_port`
3. Smoke tests run **in parallel** — each receives `SERVER_PORT` as an environment variable pointing to its respective server
4. Results are logged separately and diffed after both complete
5. Servers are shut down automatically (even on error)

### Smoke test config file

Each smoke test receives a runtime config YAML path as `ARGV[0]`. No environment variables are used — all configuration comes from the YAML file.

The config file contains:

| Key | Description |
|---|---|
| `gem_name` | The gem being tested |
| `server_port` | The port of the server this test should target (only present when `server: true`) |
| `output_dir` | Directory where tests can write extra log files to be diffed |

Any files written to `output_dir` are automatically diffed between the before and after runs and included in the report. This is useful for capturing browser console errors, screenshots, or any structured output.

```ruby
# test/smoke/rails/response_check.rb
require "yaml"
require "net/http"

config = YAML.safe_load_file(ARGV[0])
port = config.fetch("server_port")
uri = URI("http://127.0.0.1:#{port}/api/status")

res = Net::HTTP.get_response(uri)
puts "Status: #{res.code}"
puts res.body

abort "Unexpected status #{res.code}" unless res.code == "200"
```

### Selenium tests

Smoke tests are plain Ruby scripts, so you can use Selenium for browser-level A/B testing. Write browser console errors to the config's `output_dir` and they'll be diffed automatically.

```ruby
# test/smoke/rails/browser_check.rb
require "yaml"
require "selenium-webdriver"

config = YAML.safe_load_file(ARGV[0])
port = config.fetch("server_port")
output_dir = config.fetch("output_dir")

options = Selenium::WebDriver::Chrome::Options.new(args: ["--headless"])
options.add_option("goog:loggingPrefs", { browser: "ALL" })
driver = Selenium::WebDriver.for(:chrome, options: options)

begin
  driver.get("http://127.0.0.1:#{port}/")

  # Capture browser console errors
  logs = driver.manage.logs.get(:browser)
  errors = logs.select { |entry| entry.level == "SEVERE" }

  File.write(File.join(output_dir, "browser_errors.log"), errors.map(&:message).join("\n"))

  abort "Browser errors detected: #{errors.size}" unless errors.empty?
  puts "No browser errors"
ensure
  driver.quit
end
```

The report will include a diff of `browser_errors.log` between the before and after runs:

```
## Browser errors Diff
--- tmp/gem_updates/rails/before/smoke/browser_errors.log
+++ tmp/gem_updates/rails/after/smoke/browser_errors.log
@@ -0,0 +1 @@
+Uncaught TypeError: Cannot read properties of undefined
```

### Example workflow

```sh
# 1. Make sure your test suite passes first
bundle exec rake test

# 2. Create config
cat > .gem_update.yml << 'EOF'
defaults:
  server: false

rails:
  server: true
  before_port: 3000
  after_port: 3001
EOF

# 3. Write a smoke test
mkdir -p test/smoke
cat > test/smoke/rails.rb << 'RUBY'
require "yaml"
require "net/http"
config = YAML.safe_load_file(ARGV[0])
port = config.fetch("server_port")
res = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/health"))
abort "Failed: #{res.code}" unless res.code == "200"
puts "OK"
RUBY

# 4. Run the upgrade test
gem-update rails
```

### Example output

With servers enabled:

```
$ gem-update rails

== gem-update: rails ==

1. Creating worktree...
2. Running bundle update rails...
   Starting puma servers...
   Before server running on port 3000
   After server running on port 3001
3. Running smoke tests (before & after in parallel)...
5. Generating report...
============================================================
gem-update report: rails
============================================================

## Timing
  Before: 1.204s
  After:  1.387s
  Diff:   +0.183s

## Exit Status
  Before: OK
  After:  OK

## Stdout Diff
  (no differences)

## Stderr Diff
  (no differences)

## Gemfile.lock Diff
--- /Users/you/myapp/Gemfile.lock
+++ /Users/you/myapp/tmp/gem_updates/rails/worktree/Gemfile.lock
@@ -120,7 +120,7 @@
     railties (= 7.1.3)
-    rails (7.1.3)
+    rails (7.2.0)
-    actioncable (7.1.3)
+    actioncable (7.2.0)

Artifacts saved to: tmp/gem_updates/rails
```

Without servers (default):

```
$ gem-update nokogiri

== gem-update: nokogiri ==

1. Creating worktree...
2. Running bundle update nokogiri...
3. Running smoke tests (before)...
4. Running smoke tests (after)...
5. Generating report...
============================================================
gem-update report: nokogiri
============================================================

## Timing
  Before: 0.532s
  After:  0.548s
  Diff:   +0.016s

## Exit Status
  Before: OK
  After:  OK

## Stdout Diff
  (no differences)

## Stderr Diff
  (no differences)

## Gemfile.lock Diff
--- /Users/you/myapp/Gemfile.lock
+++ /Users/you/myapp/tmp/gem_updates/nokogiri/worktree/Gemfile.lock
@@ -85,7 +85,7 @@
-    nokogiri (1.15.4)
+    nokogiri (1.16.0)

Artifacts saved to: tmp/gem_updates/nokogiri
```

When a regression is caught:

```
## Exit Status
  Before: OK
  After:  FAILED

## Stdout Diff
--- tmp/gem_updates/rails/before/stdout.log
+++ tmp/gem_updates/rails/after/stdout.log
@@ -1,2 +1,2 @@
-Status: 200
+Status: 500
-Health check passed
+Health check failed

## Stderr Diff
--- tmp/gem_updates/rails/before/stderr.log
+++ tmp/gem_updates/rails/after/stderr.log
@@ -0,0 +1 @@
+Failed: 500
```

### Artifacts

Results are saved to `tmp/gem_updates/<gem_name>/`:

```
tmp/gem_updates/rails/
├── before/
│   ├── stdout.log
│   ├── stderr.log
│   ├── timing.txt
│   ├── smoke_config.yml            # runtime config passed to smoke tests
│   ├── smoke/                      # files written by tests via output_dir
│   │   └── browser_errors.log
│   ├── puma_stdout.log             # when server: true
│   ├── puma_stderr.log
│   └── puma.pid
├── after/
│   ├── stdout.log
│   ├── stderr.log
│   ├── timing.txt
│   ├── smoke_config.yml
│   ├── smoke/
│   │   └── browser_errors.log
│   ├── puma_stdout.log
│   ├── puma_stderr.log
│   └── puma.pid
├── bundle_update.log
├── gemfile_lock.diff
└── report.txt
```

### Server cleanup

Puma servers are cleaned up automatically. You don't need to worry about orphaned processes:

- **Normal exit or errors** — servers are always stopped via `begin/ensure`, even if smoke tests fail or raise exceptions.
- **Ctrl-C / SIGTERM** — signal handlers catch interrupts and shut down both servers before exiting.
- **Stale processes** — each server writes a `puma.pid` file to its log directory. If a previous run was killed ungracefully (e.g. `kill -9`), the next `gem-update` run detects the leftover pidfiles, terminates those processes, and removes the files before starting fresh.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/pauloancheta/gem-update. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/pauloancheta/gem-update/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
