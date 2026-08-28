# frozen_string_literal: true

require "open3"
require "timeout"

module RobotLab
  module Sandbox
    # Installed as RobotLab::ScriptTool.executor when this gem loads. Runs a
    # skill script unconfined when sandboxing is disabled (config.sandbox.enabled
    # is false, the default), or confined and timeout-bounded when it is enabled.
    module Executor
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

        grant   = capabilities.intersect(Capabilities.ceiling)
        sandbox = Sandbox.for(grant, skill_dir: skill_dir)
        begin
          output, status = run_with_timeout(sandbox.wrap(cmd), grant.timeout)
          RobotLab::ScriptTool.format_result(output, status)
        ensure
          sandbox.cleanup
        end
      end

      # @return [Array(String, Process::Status|nil)] output and status (nil = timed out)
      def run_with_timeout(cmd, timeout)
        Open3.popen2e(*cmd, pgroup: true) do |stdin, out, wait|
          stdin.close
          output = +""
          begin
            Timeout.timeout(timeout) { output << out.read }
          rescue Timeout::Error
            terminate(wait.pid)
            return ["#{output}\n[killed: exceeded #{timeout}s]", nil]
          end
          [output, wait.value]
        end
      end

      def terminate(pid)
        Process.kill("-TERM", Process.getpgid(pid))
      rescue StandardError
        nil
      end
    end
  end
end
