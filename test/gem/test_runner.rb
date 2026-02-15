# frozen_string_literal: true

require "test_helper"

class Gem::TestRunner < Minitest::Test
  def test_initializes_with_gem_name
    runner = Gem::Update::Runner.new("rails")
    assert_instance_of Gem::Update::Runner, runner
  end
end
