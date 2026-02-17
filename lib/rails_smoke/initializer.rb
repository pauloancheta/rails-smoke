# frozen_string_literal: true

require "fileutils"

module RailsSmoke
  class Initializer
    CONFIG_TEMPLATE = <<~YAML
      # rails-smoke configuration
      # See: https://github.com/pauloancheta/rails-smoke

      # === Gem mode (default) ===
      # Required: the gem to test upgrading
      gem_name: CHANGE_ME

      # Target version (omit for latest)
      # version: "7.2.0"

      # === Branch mode ===
      # Compare two branches directly instead of running bundle update.
      # Set before_branch/after_branch instead of gem_name.
      # before_branch: main
      # after_branch: bump-rack-3.0

      # === Shared options ===

      # Start puma servers for A/B HTTP testing
      # server: false

      # Use throwaway sandbox databases
      # sandbox: true

      # Base URL for sandbox databases (auto-detected from config/database.yml)
      # database_url_base: "postgresql://localhost"

      # Rake task to run after schema load
      # setup_task: "db:seed"

      # Ruby script to run after setup task
      # setup_script: "test/smoke/seed.rb"

      # Ports for before/after servers
      # before_port: 3000
      # after_port: 3001

      # Rails environment for servers
      # rails_env: test

      # Use an existing test command instead of manual smoke tests
      # test_command: "bundle exec rspec"
    YAML

    def initialize(project_root: Dir.pwd)
      @project_root = project_root
    end

    def run
      create_config
      create_smoke_dir
    end

    private

    def create_config
      config_path = File.join(@project_root, ".rails_smoke.yml")

      if File.exist?(config_path)
        puts ".rails_smoke.yml already exists, skipping"
        return
      end

      File.write(config_path, CONFIG_TEMPLATE)
      puts "Created .rails_smoke.yml"
    end

    def create_smoke_dir
      smoke_dir = File.join(@project_root, "test", "smoke")

      if Dir.exist?(smoke_dir)
        puts "test/smoke/ already exists, skipping"
        return
      end

      FileUtils.mkdir_p(smoke_dir)
      puts "Created test/smoke/"
    end
  end
end
