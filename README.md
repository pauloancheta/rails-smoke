# Rails Smoke

A/B smoke test gem upgrades using git worktrees. Creates a worktree with an updated gem, runs your smoke tests against both versions, and produces a comparison report with diffs and performance data.

## Installation

```sh
gem install rails-smoke
```

Or add to your Gemfile:

```ruby
gem "rails-smoke"
```

## Usage

### Quick start

```sh
# 1. Generate config file and smoke test directory
rails-smoke init

# 2. Edit .rails_smoke.yml — set gem_name and other options
# 3. Run from inside a git repository
rails-smoke
```

### What it does

rails-smoke supports two modes:

**Gem mode** (default) — tests a gem upgrade:
1. Reads `gem_name` from `.rails_smoke.yml`
2. Creates a git worktree from the current HEAD
3. Runs `bundle update <gem_name>` in the worktree
4. Runs your smoke tests against the original and updated code
5. Generates a comparison report (timing, exit status, stdout/stderr diffs, Gemfile.lock diff)
6. Cleans up the worktree

**Branch mode** — compares two git branches directly:
1. Creates worktrees for both `before_branch` and `after_branch`
2. Generates a Gemfile.lock diff between the two branches
3. Runs your smoke tests against both worktrees
4. Generates a comparison report
5. Cleans up both worktrees

Mode is determined by which fields are present in `.rails_smoke.yml`: `gem_name` triggers gem mode, `before_branch`/`after_branch` triggers branch mode.

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

Create a `.rails_smoke.yml` in your project root (or run `rails-smoke init`):

**Gem mode** (test a gem upgrade):
```yaml
gem_name: rails
server: true
version: "7.2.0"
sandbox: true
database_url_base: "postgresql://localhost"
setup_task: "db:seed"
setup_script: "test/smoke/seed.rb"
before_port: 4000
after_port: 4001
```

**Branch mode** (compare two branches):
```yaml
before_branch: main          # defaults to "main" if omitted
after_branch: bump-rack-3.0  # defaults to current branch if omitted
server: true
sandbox: true
database_url_base: "postgresql://localhost"
```

In branch mode, `after_branch` is used as the identifier for smoke test discovery (looks for `test/smoke/<after_branch>.rb` or `test/smoke/<after_branch>/*.rb`) and output directory naming.

| Key | Default | Description |
|---|---|---|
| `gem_name` | *(required in gem mode)* | The gem to test upgrading |
| `before_branch` | `main` | Base branch for comparison (branch mode) |
| `after_branch` | *(current branch)* | Branch with changes to test (branch mode) |
| `server` | `false` | Start puma servers for A/B testing |
| `version` | *(latest)* | Target version to update to (gem mode only) |
| `before_port` | `3000` | Port for the original (pre-update) server |
| `after_port` | `3001` | Port for the updated (post-update) server |
| `rails_env` | `test` | `RAILS_ENV` for both servers |
| `sandbox` | `true` | Auto-create throwaway databases for each server |
| `database_url_base` | `nil` | Base URL for throwaway DBs (e.g. `postgresql://localhost`) |
| `setup_task` | `nil` | Rake task to run after schema load (e.g. `db:seed`, `db:fixtures:load`) |
| `setup_script` | `nil` | Ruby script to run after setup_task (e.g. `test/smoke/seed.rb`) |

### Sandbox mode

When `sandbox: true` (the default), both servers run in the **same** `RAILS_ENV` (configurable via `rails_env`, defaults to `test`). Each server gets its own throwaway database via `DATABASE_URL`, so they don't interfere with each other.

The sandbox lifecycle:

1. **Create** — `rails db:create` with a unique `DATABASE_URL` for each server
2. **Schema load** — `rails db:schema:load` to set up the schema
3. **Setup task** — optional rake task (e.g. `db:seed`) to populate data
4. **Setup script** — optional Ruby script for custom seeding
5. **Run tests** — puma servers start with `DATABASE_URL` pointing to their throwaway DB
6. **Cleanup** — `rails db:drop` removes both databases after tests complete (even on error)

Database names are generated as `rails_smoke_<gem_name>_before_<pid>` and `rails_smoke_<gem_name>_after_<pid>`, so concurrent runs don't collide.

You must set `database_url_base` to your database server URL (e.g. `postgresql://localhost`) for sandbox mode to work. The generated `DATABASE_URL` is `<database_url_base>/<db_name>`.

To disable sandbox mode and manage databases yourself, set `sandbox: false`. In this case, only `RAILS_ENV` and `RACK_ENV` are set on the servers.

### How it works

When `server: true` is set for a gem:

1. If `sandbox: true`, throwaway databases are created and seeded for each server
2. A puma server starts on the original code at `before_port`
3. A puma server starts on the worktree (updated code) at `after_port`
4. Smoke tests run **in parallel** — each receives `SERVER_PORT` as an environment variable pointing to its respective server
5. Results are logged separately and diffed after both complete
6. Servers are shut down automatically (even on error)
7. If `sandbox: true`, throwaway databases are dropped

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
--- tmp/rails_smoke/rails/before/smoke/browser_errors.log
+++ tmp/rails_smoke/rails/after/smoke/browser_errors.log
@@ -0,0 +1 @@
+Uncaught TypeError: Cannot read properties of undefined
```

### Example workflow

```sh
# 1. Make sure your test suite passes first
bundle exec rake test

# 2. Create config and smoke test directory
rails-smoke init

# 3. Edit .rails_smoke.yml
cat > .rails_smoke.yml << 'EOF'
gem_name: rails
server: true
sandbox: true
database_url_base: "postgresql://localhost"
setup_task: "db:seed"
before_port: 3000
after_port: 3001
EOF

# 4. Write a smoke test
cat > test/smoke/rails.rb << 'RUBY'
require "yaml"
require "net/http"
config = YAML.safe_load_file(ARGV[0])
port = config.fetch("server_port")
res = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/health"))
abort "Failed: #{res.code}" unless res.code == "200"
puts "OK"
RUBY

# 5. Run the upgrade test
rails-smoke
```

### Example output

With servers enabled:

```
$ rails-smoke

== rails-smoke: rails ==

1. Creating worktree...
2. Running bundle update rails...
   Setting up sandbox databases...
   Starting puma servers...
   Before server running on port 3000 (test)
   After server running on port 3001 (test)
3. Running smoke tests (before & after in parallel)...
5. Generating report...
   Cleaning up sandbox databases...
============================================================
rails-smoke report: rails
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
+++ /Users/you/myapp/tmp/rails_smoke/rails/worktree/Gemfile.lock
@@ -120,7 +120,7 @@
     railties (= 7.1.3)
-    rails (7.1.3)
+    rails (7.2.0)
-    actioncable (7.1.3)
+    actioncable (7.2.0)

Artifacts saved to: tmp/rails_smoke/rails
```

Without servers (default):

```
$ rails-smoke

== rails-smoke: nokogiri ==

1. Creating worktree...
2. Running bundle update nokogiri...
3. Running smoke tests (before)...
4. Running smoke tests (after)...
5. Generating report...
============================================================
rails-smoke report: nokogiri
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
+++ /Users/you/myapp/tmp/rails_smoke/nokogiri/worktree/Gemfile.lock
@@ -85,7 +85,7 @@
-    nokogiri (1.15.4)
+    nokogiri (1.16.0)

Artifacts saved to: tmp/rails_smoke/nokogiri
```

When a regression is caught:

```
## Exit Status
  Before: OK
  After:  FAILED

## Stdout Diff
--- tmp/rails_smoke/rails/before/stdout.log
+++ tmp/rails_smoke/rails/after/stdout.log
@@ -1,2 +1,2 @@
-Status: 200
+Status: 500
-Health check passed
+Health check failed

## Stderr Diff
--- tmp/rails_smoke/rails/before/stderr.log
+++ tmp/rails_smoke/rails/after/stderr.log
@@ -0,0 +1 @@
+Failed: 500
```

### Artifacts

Results are saved to `tmp/rails_smoke/<gem_name>/`:

```
tmp/rails_smoke/rails/
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
├── sandbox/                        # when sandbox: true
│   ├── db_create_stdout.log
│   ├── db_create_stderr.log
│   ├── db_schema_load_stdout.log
│   ├── db_schema_load_stderr.log
│   ├── db_drop_stdout.log
│   └── db_drop_stderr.log
├── bundle_update.log
├── gemfile_lock.diff
└── report.txt
```

### Server cleanup

Puma servers are cleaned up automatically. You don't need to worry about orphaned processes:

- **Normal exit or errors** — servers are always stopped via `begin/ensure`, even if smoke tests fail or raise exceptions.
- **Ctrl-C / SIGTERM** — signal handlers catch interrupts and shut down both servers before exiting.
- **Stale processes** — each server writes a `puma.pid` file to its log directory. If a previous run was killed ungracefully (e.g. `kill -9`), the next `rails-smoke` run detects the leftover pidfiles, terminates those processes, and removes the files before starting fresh.
- **Sandbox databases** — throwaway databases are dropped in the `ensure` block, so they're cleaned up even if tests fail.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/pauloancheta/rails-smoke. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/pauloancheta/rails-smoke/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
