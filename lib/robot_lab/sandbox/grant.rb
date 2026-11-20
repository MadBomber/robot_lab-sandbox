# frozen_string_literal: true

module RobotLab
  module Sandbox
    # Computes the effective grant a script runs under.
    #
    # Core's `Capabilities#intersect` compares paths lexically, so a declared
    # path that sits under a ceiling root but is (or passes through) a symlink
    # pointing elsewhere survives it. {Seatbelt} then resolves symlinks and
    # would grant the outside target. This applies core's lexical check first
    # and then a second, symlink-resolved one: a path is granted only when it
    # passes both. Deny on doubt -- a path that cannot be resolved is dropped.
    module Grant
      module_function

      # @param declared [Capabilities] what the skill asked for
      # @param ceiling [Capabilities] what config permits (see {Ceiling})
      # @return [Capabilities] grant whose paths are resolved real paths
      def resolve(declared, ceiling)
        lexical = declared.intersect(ceiling)
        Capabilities.new(
          fs_read:  confine(lexical.fs_read, ceiling.fs_read),
          fs_write: confine(lexical.fs_write, ceiling.fs_write),
          network:  lexical.network,
          timeout:  lexical.timeout,
          trust:    lexical.trust
        )
      end

      # @return [Array<String>] resolved forms of the paths whose real location
      #   is inside a resolved root
      def confine(paths, roots)
        real_roots = roots.filter_map { |root| Paths.real(root) }
        paths.filter_map { |path| Paths.real(path) }
             .select { |real| Paths.inside?(real, real_roots) }
             .uniq
      end
    end
  end
end
