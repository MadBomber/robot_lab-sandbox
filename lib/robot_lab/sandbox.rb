# frozen_string_literal: true

require_relative "sandbox/version"

module RobotLab
  # Confines skill-script execution to a granted set of capabilities.
  #
  # Sandboxing is opt-in (config.sandbox.enabled). When off, every script runs
  # unconfined exactly as robot_lab core alone would run it. When on, each
  # script runs under a strategy:
  #
  # - {Sandbox::Seatbelt} on macOS — a generated deny-by-default sandbox-exec
  #   profile derived from the effective {Capabilities} grant.
  # - {Sandbox::Null} elsewhere (or for +trust: core+ skills) — a passthrough.
  #
  # OS-level confinement is therefore best-effort and platform-specific; it is
  # never a hard dependency. robot_lab core has no notion of sandboxing at
  # all -- requiring this gem is what installs confinement into
  # RobotLab::ScriptTool via {Executor}.
  module Sandbox
    class Error < StandardError; end

    module_function

    # @return [Boolean] whether sandboxing is turned on in config
    def enabled?(config = RobotLab.config)
      config.respond_to?(:sandbox) && config.sandbox && config.sandbox.enabled == true
    end

    def macos?
      RUBY_PLATFORM.include?("darwin")
    end

    # Pick a strategy for the given (already-intersected) grant.
    #
    # @param grant [Capabilities] effective grant
    # @param skill_dir [String] skill bundle root, always granted read access
    # @param macos [Boolean] whether to use the macOS strategy; defaults to the
    #   real platform check and is injectable so both branches are testable on
    #   any host without stubbing.
    # @return [#wrap, #cleanup]
    # :reek:ControlParameter -- macos: is an intentional test seam (see above).
    def for(grant, skill_dir:, macos: macos?)
      return Null.new if grant.core?
      return Seatbelt.new(grant, skill_dir: skill_dir) if macos

      warn_once_non_macos
      Null.new
    end

    def warn_once_non_macos
      return if @warned_non_macos

      @warned_non_macos = true
      RobotLab.config.logger.warn(
        "Sandbox: OS-level confinement is only available on macOS; scripts run unconfined here"
      )
    end
  end
end

require_relative "sandbox/seatbelt"
require_relative "sandbox/null"
require_relative "sandbox/executor"

unless defined?(RobotLab::ScriptTool)
  raise RobotLab::Sandbox::Error, "robot_lab must be loaded before robot_lab/sandbox"
end

RobotLab::ScriptTool.executor = RobotLab::Sandbox::Executor

if RobotLab.respond_to?(:register_extension)
  RobotLab.register_extension(:sandbox, RobotLab::Sandbox)
end
