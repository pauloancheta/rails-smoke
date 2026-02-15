# frozen_string_literal: true

require "yaml"

module Gem
  module Update
    class Config
      DEFAULTS = {
        "server" => false,
        "before_port" => 3000,
        "after_port" => 3001
      }.freeze

      def initialize(gem_name, project_root: Dir.pwd)
        @gem_name = gem_name
        @settings = load_settings(project_root)
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

      private

      def load_settings(project_root)
        path = File.join(project_root, ".gem_update.yml")
        return DEFAULTS.dup unless File.exist?(path)

        yaml = YAML.safe_load_file(path) || {}
        defaults = DEFAULTS.merge(yaml.fetch("defaults", {}))
        gem_overrides = yaml.fetch(@gem_name, {})

        defaults.merge(gem_overrides)
      end
    end
  end
end
