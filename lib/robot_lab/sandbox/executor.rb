# frozen_string_literal: true

require "open3"

module RobotLab
  module Sandbox
    # Installed as RobotLab::ScriptTool.executor when this gem loads. Runs a
    # skill script unconfined when sandboxing is disabled (config.sandbox.enabled
    # is false, the default), or confined and timeout-bounded when it is enabled.
    module Executor
      # Seconds a timed-out process group gets between SIGTERM and SIGKILL.
      KILL_GRACE = 2
      # Seconds between liveness checks while waiting out KILL_GRACE.
      POLL       = 0.05

      module_function

      # @param cmd [Array<String>] command to run
      # @param capabilities [Capabilities] declared capabilities (from SKILL.md)
      # @param skill_dir [String] skill bundle root
      # @return [String] combined stdout+stderr, or an error string on failure
      def call(cmd, capabilities:, skill_dir:)
        unless Sandbox.enabled?
          output, status = Open3.capture2e(*cmd)
          return RobotLab::ScriptTool.format_result(output, status)
        end

        grant   = Grant.resolve(capabilities, Ceiling.build)
        sandbox = Sandbox.for(grant, skill_dir: skill_dir)
        begin
          output, status = run_with_timeout(sandbox.wrap(cmd), grant.timeout)
          format_result(output, status)
        ensure
          sandbox.cleanup
        end
      end

      # Run cmd in its own process group, bounded by timeout seconds overall:
      # the bound covers the process itself, not just its output, so a script
      # that closes stdout and keeps running is still killed.
      #
      # @return [Array(String, Process::Status|nil)] output and status (nil =
      #   timed out; the output is whatever was captured before the kill)
      def run_with_timeout(cmd, timeout)
        limit = Coerce.duration(timeout)
        Open3.popen2e(child_env, *cmd, pgroup: true) do |stdin, out, wait|
          stdin.close
          supervise(out, wait, limit)
        end
      end

      # Collect the output of a running child until it finishes or limit
      # seconds pass, killing its process group in the latter case.
      #
      # @param out [IO] the child's combined stdout+stderr
      # @param wait [Process::Waiter] the child's wait thread
      # @return [Array(String, Process::Status|nil)]
      def supervise(out, wait, limit)
        buffer = +""
        reader = Thread.new { drain(out, buffer) }
        return [text(buffer), wait.value] if finished_within?(limit, wait, reader)

        terminate(wait.pid)
        reader.join(POLL)
        reader.kill
        ["#{text(buffer)}\n[killed: exceeded #{limit}s]", nil]
      end

      # A correct PWD lets the shell skip getcwd(), which fails noisily under
      # Seatbelt because the working directory's ancestors are not readable.
      # It grants no access -- it is the value the shell would have computed.
      def child_env
        { "PWD" => Dir.pwd }
      end

      # Append everything readable from io to buffer until EOF.
      def drain(io, buffer)
        loop { buffer << io.readpartial(4096) }
      rescue IOError
        nil # EOF (EOFError is an IOError), or the stream was closed under us
      end

      # @return [Boolean] whether the process exited and its output hit EOF
      #   before limit seconds elapsed
      def finished_within?(limit, wait, reader)
        deadline = monotonic + limit
        return false unless wait.join(limit)

        reader.join([deadline - monotonic, 0].max) ? true : false
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # The captured bytes as a String in the default external encoding (what
      # a plain read would have returned).
      def text(buffer)
        buffer.dup.force_encoding(Encoding.default_external)
      end

      # Stop the process group led by pid: SIGTERM, then SIGKILL for whatever
      # is still alive after grace seconds. Never raises.
      def terminate(pid, grace: KILL_GRACE)
        return nil unless signal_group("TERM", pid)

        deadline = monotonic + grace
        sleep(POLL) while group_alive?(pid) && monotonic < deadline
        signal_group("KILL", pid)
        nil
      end

      def group_alive?(pid)
        signal_group(0, pid)
      end

      # Signal the process group whose id is pid (popen2e's pgroup: true makes
      # the child its own group leader, so pgid == pid).
      #
      # @return [Boolean] whether the signal was delivered. Refuses pids <= 1:
      #   a group id of 0, 1 or a negative number would address this process's
      #   own group, launchd, or every process we may signal.
      def signal_group(signal, pid)
        return false unless pid.is_a?(Integer) && pid > 1

        Process.kill(signal, -pid)
        true
      rescue StandardError
        false # no such group (already gone), or not ours to signal
      end

      # Core's ScriptTool.format_result prints "Error (exit ):" for a process
      # that died from a signal (no exit status) -- name the signal instead.
      def format_result(output, status)
        return "Error (killed by signal #{status.termsig}):\n#{output}" if status&.signaled?

        RobotLab::ScriptTool.format_result(output, status)
      end
    end
  end
end
