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
require "net/http"

res = Net::HTTP.get_response(URI("http://127.0.0.1:#{ENV["SERVER_PORT"]}/health"))
abort "Health check failed: #{res.code}" unless res.code == "200"

puts "Health check passed"
```

Without the server option, smoke tests run via `bundle exec ruby <file>` in each directory (original and worktree). They should exit 0 on success and non-zero on failure.

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
  before_port: 4000
  after_port: 4001
```

- **`defaults`** — global settings applied to all gems
- **`<gem_name>`** — per-gem overrides, merged on top of defaults

| Key | Default | Description |
|---|---|---|
| `server` | `false` | Start puma servers for A/B testing |
| `before_port` | `3000` | Port for the original (pre-update) server |
| `after_port` | `3001` | Port for the updated (post-update) server |

### How it works

When `server: true` is set for a gem:

1. A puma server starts on the original code at `before_port`
2. A puma server starts on the worktree (updated code) at `after_port`
3. Smoke tests run **in parallel** — each receives `SERVER_PORT` as an environment variable pointing to its respective server
4. Results are logged separately and diffed after both complete
5. Servers are shut down automatically (even on error)

### Smoke test environment variables

When servers are enabled, your smoke test receives:

| Variable | Description |
|---|---|
| `SERVER_PORT` | The port of the server this test should target |

```ruby
# test/smoke/rails/response_check.rb
require "net/http"

port = ENV.fetch("SERVER_PORT")
uri = URI("http://127.0.0.1:#{port}/api/status")

res = Net::HTTP.get_response(uri)
puts "Status: #{res.code}"
puts res.body

abort "Unexpected status #{res.code}" unless res.code == "200"
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
require "net/http"
port = ENV.fetch("SERVER_PORT", "3000")
res = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/health"))
abort "Failed: #{res.code}" unless res.code == "200"
puts "OK"
RUBY

# 4. Run the upgrade test
gem-update rails
```

### Output

Results are saved to `tmp/gem_updates/<gem_name>/`:

```
tmp/gem_updates/rails/
├── before/
│   ├── stdout.log
│   ├── stderr.log
│   ├── timing.txt
│   ├── puma_stdout.log   # when server: true
│   └── puma_stderr.log
├── after/
│   ├── stdout.log
│   ├── stderr.log
│   ├── timing.txt
│   ├── puma_stdout.log
│   └── puma_stderr.log
├── bundle_update.log
├── gemfile_lock.diff
└── report.txt
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/pauloancheta/gem-update. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/pauloancheta/gem-update/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
