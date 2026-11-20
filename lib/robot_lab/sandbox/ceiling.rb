# frozen_string_literal: true

module RobotLab
  module Sandbox
    # Builds the capability ceiling from `config.sandbox`, coercing every value
    # (see {Coerce}). Used instead of core's `Capabilities.ceiling`, which reads
    # the raw values by truthiness and so turns the env-var string "false" into
    # a network grant.
    module Ceiling
      module_function

      # @return [Capabilities] the ceiling; nothing beyond core's defaults when
      #   the config has no sandbox section
      def build(config = RobotLab.config)
        section = config.respond_to?(:sandbox) ? config.sandbox : nil
        return Capabilities.new(fs_read: ["."]) unless section

        Capabilities.new(
          fs_read:  Coerce.paths(section.fs_read, ["."]),
          fs_write: Coerce.paths(section.fs_write, []),
          network:  Coerce.truthy?(section.network, ambiguous: false),
          timeout:  Coerce.timeout(section.timeout)
        )
      end
    end
  end
end
