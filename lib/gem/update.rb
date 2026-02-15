# frozen_string_literal: true

require_relative "update/version"
require_relative "update/worktree"
require_relative "update/gem_updater"
require_relative "update/smoke_test"
require_relative "update/report"
require_relative "update/runner"

module Gem
  module Update
    class Error < StandardError; end
  end
end
