# frozen_string_literal: true

require "open3"
require "yaml"

module RailsSmoke
  class SmokeTest
    Result = Struct.new(:stdout, :stderr, :elapsed, :success, keyword_init: true)

    def initialize(gem_name, test_dir: Dir.pwd)
      @gem_name = gem_name
      @test_dir = test_dir
    end

    def test_files
      Dir.glob(File.join(@test_dir, "test", "smoke", "**", "*.rb")).sort
    end

    def run(directory:, output_dir:, server_port: nil)
      files = test_files
      if files.empty?
        warn "No smoke tests found. Expected test/smoke/*.rb"
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
        stdout, stderr, status = Open3.capture3(
          "bundle", "exec", "ruby", file, config_path,
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

    def run_command(command:, directory:, output_dir:)
      FileUtils.mkdir_p(output_dir)

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      stdout, stderr, status = Bundler.with_unbundled_env do
        Open3.capture3(command, chdir: directory)
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      File.write(File.join(output_dir, "stdout.log"), stdout)
      File.write(File.join(output_dir, "stderr.log"), stderr)
      File.write(File.join(output_dir, "timing.txt"), format("%.3fs", elapsed))

      Result.new(stdout: stdout, stderr: stderr, elapsed: elapsed, success: status.success?)
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
