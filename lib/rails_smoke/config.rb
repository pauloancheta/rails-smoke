# frozen_string_literal: true

require "yaml"
require "erb"
require "open3"

module RailsSmoke
  class Config
    DEFAULTS = {
      "server" => false,
      "before_port" => 3000,
      "after_port" => 3001,
      "rails_env" => "test",
      "sandbox" => true,
      "setup_task" => nil,
      "setup_script" => nil,
      "database_url_base" => nil,
      "test_command" => nil
    }.freeze

    def initialize(project_root: Dir.pwd)
      @project_root = project_root
      @settings = load_settings(project_root)
    end

    def gem_name
      @settings["gem_name"]
    end

    def before_branch
      @settings["before_branch"]
    end

    def after_branch
      @settings["after_branch"]
    end

    def mode
      @mode ||= if @settings.key?("before_branch") || @settings.key?("after_branch")
                  "branch"
                else
                  "gem"
                end
    end

    def identifier
      mode == "branch" ? after_branch : gem_name
    end

    def server?
      @settings["server"]
    end

    def before_port
      @settings["before_port"]
    end

    def after_port
      @settings["after_port"]
    end

    def version
      @settings["version"]
    end

    def rails_env
      @settings["rails_env"]
    end

    def sandbox?
      @settings["sandbox"]
    end

    def setup_task
      @settings["setup_task"]
    end

    def setup_script
      @settings["setup_script"]
    end

    def test_command
      @settings["test_command"]
    end

    def database_url_base
      @settings["database_url_base"] || detect_database_url_base
    end

    private

    def load_settings(project_root)
      path = File.join(project_root, ".rails_smoke.yml")

      unless File.exist?(path)
        raise RailsSmoke::Error, "Config file not found: .rails_smoke.yml\nRun `rails-smoke init` to create one."
      end

      yaml = YAML.safe_load_file(path) || {}
      settings = DEFAULTS.merge(yaml)

      validate!(settings)

      settings
    end

    def validate!(settings)
      has_gem = settings.key?("gem_name") && settings["gem_name"].is_a?(String) && !settings["gem_name"].strip.empty?
      has_branch = settings.key?("before_branch") || settings.key?("after_branch")

      if has_gem && has_branch
        raise RailsSmoke::Error, "Cannot set both gem_name and branch fields (before_branch/after_branch)"
      end

      if has_branch
        validate_branch_mode!(settings)
      else
        validate_gem_mode!(settings)
      end
    end

    def validate_gem_mode!(settings)
      gem_name = settings["gem_name"]
      return unless gem_name.nil? || (gem_name.is_a?(String) && gem_name.strip.empty?)

      raise RailsSmoke::Error, "gem_name is required in .rails_smoke.yml"
    end

    def validate_branch_mode!(settings)
      settings["before_branch"] ||= "main"
      settings["after_branch"] ||= current_git_branch
    end

    def detect_database_url_base
      @detect_database_url_base ||= build_database_url_base
    end

    def build_database_url_base
      db_config_path = File.join(@project_root, "config", "database.yml")
      return nil unless File.exist?(db_config_path)

      raw = File.read(db_config_path)
      erb_result = ERB.new(raw).result
      db_yaml = YAML.safe_load(erb_result, permitted_classes: [Symbol]) || {}

      env_config = db_yaml[rails_env]
      return nil unless env_config.is_a?(Hash)

      adapter = env_config["adapter"]
      return nil if adapter.nil? || adapter.strip.empty?

      scheme = adapter_to_scheme(adapter)
      return nil unless scheme

      return scheme if scheme == "sqlite3"

      host = env_config["host"] || "localhost"
      port = env_config["port"]
      username = env_config["username"]
      password = env_config["password"]

      userinfo = if username && !username.empty?
                   password && !password.empty? ? "#{username}:#{password}@" : "#{username}@"
                 end

      port_part = port ? ":#{port}" : ""

      "#{scheme}://#{userinfo}#{host}#{port_part}"
    end

    def adapter_to_scheme(adapter)
      case adapter
      when "postgresql" then "postgresql"
      when "mysql2" then "mysql2"
      when "sqlite3" then "sqlite3"
      end
    end

    def current_git_branch
      stdout, _, status = Open3.capture3("git", "rev-parse", "--abbrev-ref", "HEAD")
      raise RailsSmoke::Error, "Failed to detect current git branch" unless status.success?

      stdout.strip
    end
  end
end
