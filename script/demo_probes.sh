#!/usr/bin/env bash
#
# Demo: Branch-mode probes with a minimal Rails app
#
# Creates a tiny Rails 7.2 app, sets up two branches with a code change
# between them, and runs rails-smoke with probes: true so you can inspect
# the output.
#
# Usage: script/demo_probes.sh
#
set -euo pipefail

GEM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_DIR="/tmp/rails_smoke_demo_$$"

echo "=== Setting up demo app in $DEMO_DIR ==="
echo ""

# 1. Create a minimal Rails app with Rails 7.2
echo "1. Installing Rails 7.2 and generating app..."
gem install rails -v "~> 7.2.0" --no-document --conservative 2>/dev/null || true
RAILS_72_VERSION=$(gem list rails --exact | grep -oE '7\.2\.[0-9]+' | head -1)
rails "_${RAILS_72_VERSION}_" new "$DEMO_DIR" \
  --skip-git --skip-docker --skip-action-mailbox \
  --skip-action-text --skip-action-cable \
  --skip-hotwire --skip-jbuilder --skip-test --skip-system-test \
  --skip-bootsnap --skip-bundle --quiet

cd "$DEMO_DIR"

# 2. Add rails-smoke to Gemfile (pointing to local dev copy)
echo "" >> Gemfile
echo "gem \"rails-smoke\", path: \"$GEM_DIR\"" >> Gemfile

# 3. Initialize git and create the "before" branch
git init --quiet
bundle install --quiet
git add -A
git commit -m "Rails 7.2 app" --quiet

git checkout -b before-branch --quiet
git checkout -b after-branch --quiet

# 4. Add a model and initializer on the "after" branch to create a probe diff
echo ""
echo "2. Adding code changes on after-branch..."

mkdir -p app/models app/jobs app/mailers

cat > app/models/widget.rb <<'RUBY'
class Widget
  def self.description
    "A demo widget"
  end
end
RUBY

cat > app/jobs/notification_job.rb <<'RUBY'
class NotificationJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    # send notification
  end
end
RUBY

cat > app/jobs/welcome_email_job.rb <<'RUBY'
class WelcomeEmailJob < ApplicationJob
  queue_as :mailers

  def perform(user_id)
    # send welcome email
  end
end
RUBY

cat > app/mailers/user_mailer.rb <<'RUBY'
class UserMailer < ApplicationMailer
  def welcome
    mail(to: "user@example.com", subject: "Welcome")
  end

  def confirmation
    mail(to: "user@example.com", subject: "Confirm your account")
  end
end
RUBY

cat > config/initializers/demo.rb <<'RUBY'
Rails.application.config.demo_setting = true
RUBY

git add -A
git commit -m "Add widget model and demo initializer" --quiet

# 5. Write rails-smoke config
cat > .rails_smoke.yml <<YAML
before_branch: before-branch
after_branch: after-branch
sandbox: false
probes: true
YAML

echo ""
echo "3. Running rails-smoke with probes..."
echo ""

# 6. Run rails-smoke
bundle exec ruby "$GEM_DIR/exe/rails-smoke"

# 7. Show the output
echo ""
echo "=== Probe outputs ==="
echo ""
echo "--- BEFORE: probe_boot.txt ---"
cat rails_smoke_artifacts/before/smoke/probe_boot.txt 2>/dev/null || echo "(not found)"
echo ""
echo "--- BEFORE: probe_eager_load.txt ---"
head -5 rails_smoke_artifacts/before/smoke/probe_eager_load.txt 2>/dev/null || echo "(not found)"
echo "  ..."
echo ""
echo "--- AFTER: probe_boot.txt ---"
cat rails_smoke_artifacts/after/smoke/probe_boot.txt 2>/dev/null || echo "(not found)"
echo ""
echo "--- AFTER: probe_eager_load.txt ---"
head -5 rails_smoke_artifacts/after/smoke/probe_eager_load.txt 2>/dev/null || echo "(not found)"
echo "  ..."
echo ""
echo "--- AFTER: probe_jobs.txt ---"
cat rails_smoke_artifacts/after/smoke/probe_jobs.txt 2>/dev/null || echo "(not found)"
echo ""
echo "--- AFTER: probe_mailers.txt ---"
cat rails_smoke_artifacts/after/smoke/probe_mailers.txt 2>/dev/null || echo "(not found)"
echo ""
echo "--- AFTER: probe_rake_tasks.txt ---"
head -10 rails_smoke_artifacts/after/smoke/probe_rake_tasks.txt 2>/dev/null || echo "(not found)"
echo "  ..."
echo ""
echo "--- AFTER: probe_routes.txt ---"
head -10 rails_smoke_artifacts/after/smoke/probe_routes.txt 2>/dev/null || echo "(not found)"
echo "  ..."
echo ""
echo "--- AFTER: probe_native_extensions.txt ---"
cat rails_smoke_artifacts/after/smoke/probe_native_extensions.txt 2>/dev/null || echo "(not found)"
echo ""
echo "--- AFTER: probe_shared_libs.txt ---"
head -20 rails_smoke_artifacts/after/smoke/probe_shared_libs.txt 2>/dev/null || echo "(not found)"
echo "  ..."
echo ""
echo "--- AFTER: probe_system_deps.txt ---"
cat rails_smoke_artifacts/after/smoke/probe_system_deps.txt 2>/dev/null || echo "(not found)"
echo ""
echo "--- AFTER: probe_ruby_warnings.txt ---"
head -10 rails_smoke_artifacts/after/smoke/probe_ruby_warnings.txt 2>/dev/null || echo "(not found)"
echo "  ..."
echo ""
echo "--- AFTER: probe_ssl_certs.txt ---"
cat rails_smoke_artifacts/after/smoke/probe_ssl_certs.txt 2>/dev/null || echo "(not found)"
echo ""
echo "=== Reports ==="
cat rails_smoke_artifacts/report.txt 2>/dev/null || echo "(report not found)"
echo ""
echo "=== Full artifacts at: $DEMO_DIR/rails_smoke_artifacts/ ==="
echo "=== Demo app at: $DEMO_DIR ==="
