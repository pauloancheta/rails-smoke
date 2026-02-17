# frozen_string_literal: true

# Probe script: native_gems
#
# Discovers gems with native C extensions and their linked shared libraries.
# Writes probe_native_extensions.txt and probe_shared_libs.txt to output_dir.
#
# Usage: bundle exec ruby native_gems.rb <config_path>
# The config YAML must contain "output_dir".
#
# This script is self-contained — it does NOT require "rails_smoke".

require "yaml"
require "open3"

config = YAML.safe_load_file(ARGV[0])
output_dir = config.fetch("output_dir")

# --- Native Extensions ---

native_gems = Gem.loaded_specs.values
  .select { |spec| spec.extensions.any? }
  .sort_by(&:name)

ext_output = +""
ext_output << "status: OK\n"
ext_output << "native_gems:\n"
native_gems.each do |spec|
  ext_output << "  #{spec.name} #{spec.version}\n"
  spec.extensions.each do |ext|
    ext_output << "    extensions: #{ext}\n"
  end
end

File.write(File.join(output_dir, "probe_native_extensions.txt"), ext_output)

# --- Shared Libraries ---

lib_tool = if RUBY_PLATFORM =~ /darwin/
  "otool -L"
else
  "ldd"
end

libs_output = +""
libs_output << "status: OK\n"
libs_output << "shared_libs:\n"

native_gems.each do |spec|
  so_files = Dir.glob(File.join(spec.gem_dir, "**/*.{so,bundle,dylib}"))
  next if so_files.empty?

  libs_output << "  #{spec.name} #{spec.version}\n"
  so_files.sort.each do |so_file|
    libs_output << "    #{so_file}:\n"
    stdout, _stderr, status = Open3.capture3("#{lib_tool} #{so_file}")
    if status.success?
      stdout.each_line do |line|
        lib = line.strip
        next if lib.empty? || lib.end_with?(":")
        # Extract just the library name
        lib_name = lib.split(/\s/).first
        libs_output << "      #{lib_name}\n" if lib_name && !lib_name.empty?
      end
    else
      libs_output << "      (#{lib_tool} failed)\n"
    end
  end
end

File.write(File.join(output_dir, "probe_shared_libs.txt"), libs_output)

exit 0
