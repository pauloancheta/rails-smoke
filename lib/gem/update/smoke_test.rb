# frozen_string_literal: true

require "open3"
require "yaml"

module Gem
  module Update
    class SmokeTest
      Result = Struct.new(:stdout, :stderr, :elapsed, :success, keyword_init: true)

      def initialize(gem_name)
        @gem_name = gem_name
      end

      def test_files
        single = File.join("test", "smoke", "#{@gem_name}.rb")
        dir = File.join("test", "smoke", @gem_name)

        files = []
        files << single if File.exist?(single)
        files.concat(Dir.glob(File.join(dir, "*.rb")).sort) if File.directory?(dir)
        files
      end

      def run(directory:, output_dir:, server_port: nil)
        files = test_files
        if files.empty?
          warn "No smoke tests found for '#{@gem_name}'. " \
               "Expected test/smoke/#{@gem_name}.rb or test/smoke/#{@gem_name}/*.rb"
          return Result.new(stdout: "", stderr: "No smoke tests found", elapsed: 0, success: false)
        end

        FileUtils.mkdir_p(output_dir)
        smoke_output_dir = File.join(output_dir, "smoke")
        FileUtils.mkdir_p(smoke_output_dir)

        config_path = write_runtime_config(output_dir, server_port, smoke_output_dir)

        all_stdout = +""
        all_stderr = +""
        all_success = true
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        files.each do |file|
          abs_file = File.expand_path(file, Dir.pwd)
          stdout, stderr, status = Open3.capture3(
            "bundle", "exec", "ruby", abs_file, config_path,
            chdir: directory
          )
          all_stdout << stdout
          all_stderr << stderr
          all_success = false unless status.success?
        end

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

        File.write(File.join(output_dir, "stdout.log"), all_stdout)
        File.write(File.join(output_dir, "stderr.log"), all_stderr)
        File.write(File.join(output_dir, "timing.txt"), format("%.3fs", elapsed))

        Result.new(stdout: all_stdout, stderr: all_stderr, elapsed: elapsed, success: all_success)
      end

      private

      def write_runtime_config(output_dir, server_port, smoke_output_dir)
        config = {
          "gem_name" => @gem_name,
          "output_dir" => File.expand_path(smoke_output_dir)
        }
        config["server_port"] = server_port if server_port

        path = File.join(output_dir, "smoke_config.yml")
        File.write(path, YAML.dump(config))
        File.expand_path(path)
      end
    end
  end
end
