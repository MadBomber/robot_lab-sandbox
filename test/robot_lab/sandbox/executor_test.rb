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
        output = tool.call
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

      def elapsed
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      end

      # --- timeout bounds the whole execution ---

      def test_timeout_returns_partial_output_with_killed_marker
        output, status = Executor.run_with_timeout(["bash", "-c", "echo partial; sleep 5"], 0.5)
        assert_nil status
        assert_includes output, "partial"
        assert_includes output, "[killed: exceeded 0.5s]"
      end

      def test_timeout_kills_script_that_closed_its_output
        status = :unset
        took   = elapsed do
          _output, status = Executor.run_with_timeout(["bash", "-c", "exec >/dev/null 2>&1; sleep 5"], 0.5)
        end
        assert_nil status
        assert_operator took, :<, 3
      end

      def test_timeout_escalates_to_kill_when_term_is_ignored
        status = :unset
        took   = elapsed do
          _output, status = Executor.run_with_timeout(["bash", "-c", "trap \"\" TERM; echo ign; sleep 8"], 0.3)
        end
        assert_nil status
        assert_operator took, :<, 0.3 + Executor::KILL_GRACE + 2
      end

      def test_timeout_kills_background_children_left_holding_the_pipe
        marker = File.join(Dir.tmpdir, "rl_bg_#{Process.pid}")
        script = "(sleep 2; echo late > #{marker}) & echo started"
        output, status = Executor.run_with_timeout(["bash", "-c", script], 0.5)
        assert_nil status
        assert_includes output, "started"
        sleep 2.5
        refute File.exist?(marker)
      ensure
        File.delete(marker) if marker && File.exist?(marker)
      end

      def test_malformed_timeout_does_not_crash_run_with_timeout
        [nil, true, [5], "abc", -1].each do |timeout|
          output, status = Executor.run_with_timeout(["bash", "-c", "echo ok"], timeout)
          assert status.success?, timeout.inspect
          assert_includes output, "ok"
        end
      end

      def test_terminate_kills_a_group_that_ignores_term
        pid = spawn("bash", "-c", "trap \"\" TERM; sleep 30", pgroup: true)
        sleep 0.3
        assert_nil Executor.terminate(pid, grace: 0.2)
        _pid, status = Process.wait2(pid)
        assert_equal Signal.list["KILL"], status.termsig
      end

      def test_signal_group_refuses_unsafe_pids
        [-1, 0, 1, nil, "123"].each { |pid| refute Executor.signal_group(0, pid), pid.inspect }
        refute Executor.group_alive?(-1)
      end

      def test_signal_group_reports_missing_group
        pid = spawn("true", pgroup: true)
        Process.wait(pid)
        refute Executor.signal_group(0, pid)
      end

      # --- result formatting ---

      def test_format_result_names_the_signal_for_a_signaled_process
        pid = spawn("bash", "-c", "kill -KILL $$")
        _pid, status = Process.wait2(pid)
        assert_equal "Error (killed by signal 9):\nout", Executor.format_result("out", status)
      end

      def test_format_result_delegates_to_core_otherwise
        _out, ok = Open3.capture2e("true")
        _out, failed = Open3.capture2e("false")
        assert_equal "out", Executor.format_result("out", ok)
        assert_equal "Error (exit 1):\nout", Executor.format_result("out", failed)
        assert_equal "Error (timed out):\nout", Executor.format_result("out", nil)
      end

      # --- confined runs ---

      def test_confined_run_has_no_getcwd_noise
        skip "Seatbelt is macOS-only" unless Sandbox.macos?

        Dir.mktmpdir do |dir|
          RobotLab.config.sandbox.enabled = true
          Dir.chdir(dir) do
            out = Executor.call(["bash", "-c", "echo ran"], capabilities: Capabilities.new, skill_dir: Dir.tmpdir)
            assert_equal "ran\n", out
          end
        end
      ensure
        RobotLab.config.sandbox.enabled = false
      end

      def test_child_env_carries_the_real_working_directory
        assert_equal({ "PWD" => Dir.pwd }, Executor.child_env)
      end

      def test_drain_and_text
        reader, writer = IO.pipe
        writer.write("h\u00e9llo")
        writer.close
        buffer = +""
        assert_nil Executor.drain(reader, buffer)
        assert_equal "h\u00e9llo", Executor.text(buffer)
        assert_equal Encoding.default_external, Executor.text(buffer).encoding
      ensure
        reader&.close
      end
    end
  end
end
