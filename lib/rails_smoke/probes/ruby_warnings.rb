# frozen_string_literal: true

# Probe script: ruby_warnings
#
# Boots the Rails app in a subprocess with RUBYOPT=-W:deprecated to capture
# Ruby deprecation warnings. Writes probe_ruby_warnings.txt to output_dir.
#
# Usage: bundle exec ruby ruby_warnings.rb <config_path>
# The config YAML must contain "output_dir".
#
# This script is self-contained — it does NOT require "rails_smoke".

require "yaml"
require "open3"

config = YAML.safe_load_file(ARGV[0])
output_dir = config.fetch("output_dir")

env = { "RUBYOPT" => "-W:deprecated" }
cmd = ["bundle", "exec", "ruby", "-e", 'require "./config/environment"']

_stdout, stderr, status = Open3.capture3(env, *cmd)

output = +""

if status.success?
  output << "status: OK\n"
  output << "warnings:\n"

  warnings = stderr.lines
    .map(&:strip)
    .reject(&:empty?)
    .uniq
    .sort

  warnings.each { |w| output << "  #{w}\n" }
else
  output << "status: FAILED\n"
  output << "error:\n#{stderr}\n"
end

File.write(File.join(output_dir, "probe_ruby_warnings.txt"), output)

exit 0
