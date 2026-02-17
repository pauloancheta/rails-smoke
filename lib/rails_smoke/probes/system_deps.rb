# frozen_string_literal: true

# Probe script: system_deps
#
# Captures versions of common system binaries to detect missing or changed
# dependencies after OS/infra upgrades.
# Writes probe_system_deps.txt to output_dir.
#
# Usage: bundle exec ruby system_deps.rb <config_path>
# The config YAML must contain "output_dir".
#
# This script is self-contained — it does NOT require "rails_smoke".

require "yaml"
require "open3"
require "timeout"

config = YAML.safe_load_file(ARGV[0])
output_dir = config.fetch("output_dir")

BINARIES = [
  ["convert", "--version"],
  ["ffmpeg", "-version"],
  ["git", "--version"],
  ["node", "--version"],
  ["openssl", "version"],
  ["psql", "--version"],
  ["redis-server", "--version"],
  ["ruby", "--version"],
].freeze

output = +""
output << "status: OK\n"
output << "system_deps:\n"

BINARIES.each do |binary, flag|
  version = begin
    stdout, _stderr, status = Timeout.timeout(5) do
      Open3.capture3(binary, flag)
    end
    if status.success?
      stdout.lines.first&.strip || "(empty output)"
    else
      "(not found)"
    end
  rescue Errno::ENOENT
    "(not found)"
  rescue Timeout::Error
    "(timeout)"
  end

  output << "  #{binary}: #{version}\n"
end

File.write(File.join(output_dir, "probe_system_deps.txt"), output)

exit 0
