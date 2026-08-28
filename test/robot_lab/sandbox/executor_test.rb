# frozen_string_literal: true

require "test_helper"

module RobotLab
  module Sandbox
    class ExecutorTest < Minitest::Test
      FIXTURE_SCRIPT = File.expand_path(
        "../../fixtures/skills/scripted_skill/scripts/hello.sh", __dir__
      )

      def test_installs_itself_as_script_tool_executor
        assert_equal Executor, RobotLab::ScriptTool.executor
      end

      def test_call_unconfined_when_sandbox_disabled
        refute Sandbox.enabled?
        out = Executor.call(
          ["bash", "-c", "echo plain"], capabilities: Capabilities.new, skill_dir: Dir.pwd
        )
        assert_includes out, "plain"
      end

      def test_call_confined_when_sandbox_enabled
        skip "Seatbelt is macOS-only" unless Sandbox.macos?

        RobotLab.config.sandbox.enabled = true
        tool   = ScriptTool.from_path(FIXTURE_SCRIPT)
        output = tool.call({})
        assert_includes output, "Hello from AgentSkills script!"
      ensure
        RobotLab.config.sandbox.enabled = false
      end

      def test_run_with_timeout_kills_long_command
        output, status = Executor.run_with_timeout(%w[sleep 5], 0.2)
        assert_nil status
        assert_includes output, "killed"
      end

      def test_run_with_timeout_returns_output_within_budget
        output, status = Executor.run_with_timeout(["bash", "-c", "echo quick"], 10)
        assert status.success?
        assert_includes output, "quick"
      end

      def test_terminate_swallows_errors_for_dead_pid
        assert_nil Executor.terminate(-1)
      end
    end
  end
end
