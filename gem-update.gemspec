# frozen_string_literal: true

require_relative "lib/gem/update/version"

Gem::Specification.new do |spec|
  spec.name = "gem-update"
  spec.version = Gem::Update::VERSION
  spec.authors = ["Paulo Ancheta"]
  spec.email = ["paulo.ancheta@gmail.com"]

  spec.summary = "A/B smoke test gem upgrades using git worktrees"
  spec.description = "Creates a git worktree with an updated gem, runs smoke tests in both " \
                     "environments, and produces a comparison report with diffs and performance data."
  spec.homepage = "https://github.com/pauloancheta/gem-update"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
