# frozen_string_literal: true

require "open3"

module RailsSmoke
  module DiffHelpers
    private

    def text_diff(before_text, after_text, label)
      return "" if before_text == after_text

      before_file = File.join(@output_dir, "before", "#{label}.log")
      after_file = File.join(@output_dir, "after", "#{label}.log")

      diff, = Open3.capture3("diff", "-u", before_file, after_file)
      diff
    end

    def smoke_output_diffs
      before_smoke = File.join(@output_dir, "before", "smoke")
      after_smoke = File.join(@output_dir, "after", "smoke")
      return [] unless File.directory?(before_smoke) && File.directory?(after_smoke)

      before_files = Dir.glob(File.join(before_smoke, "**", "*"))
                        .select { |f| File.file?(f) }
                        .map { |f| f.delete_prefix("#{before_smoke}/") }

      after_files = Dir.glob(File.join(after_smoke, "**", "*"))
                       .select { |f| File.file?(f) }
                       .map { |f| f.delete_prefix("#{after_smoke}/") }

      (before_files | after_files).sort.map do |relative|
        before_path = File.join(before_smoke, relative)
        after_path = File.join(after_smoke, relative)
        label = File.basename(relative, File.extname(relative)).tr("_", " ").capitalize

        if File.exist?(before_path) && File.exist?(after_path)
          diff, = Open3.capture3("diff", "-u", before_path, after_path)
          [label, diff]
        elsif File.exist?(after_path)
          [label, "  (new file in after)\n#{File.read(after_path)}"]
        else
          [label, "  (missing in after)"]
        end
      end
    end

    def gemfile_lock_diff
      diff_file = File.join(@output_dir, "gemfile_lock.diff")
      return nil unless File.exist?(diff_file)

      File.read(diff_file)
    end
  end
end
