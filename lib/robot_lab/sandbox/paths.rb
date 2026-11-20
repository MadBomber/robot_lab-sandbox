# frozen_string_literal: true

module RobotLab
  module Sandbox
    # Path resolution shared by {Grant} and {Seatbelt}.
    module Paths
      module_function

      # Resolve to the real (symlink-free) path the kernel matches against. macOS
      # symlinks /tmp -> /private/tmp, /var -> /private/var, etc., so logical
      # paths would never match. For a not-yet-existing target, resolve the
      # nearest existing ancestor and re-append the remainder.
      #
      # @return [String, nil] nil when the path cannot be resolved (a symlink
      #   loop, a dangling symlink, an unreadable ancestor) -- callers must treat that as "no grant"
      def real(path)
        existing = File.expand_path(path.to_s)
        rest     = []
        until File.exist?(existing) || File.symlink?(existing) || existing == "/"
          rest.unshift(File.basename(existing))
          existing = File.dirname(existing)
        end
        File.join(File.realpath(existing), *rest)
      rescue StandardError
        nil
      end

      # @param path [String] an already-resolved path
      # @param roots [Array<String>] already-resolved roots
      # @return [Boolean] whether path is one of the roots or lies beneath one
      def inside?(path, roots)
        roots.any? { |root| path == root || path.start_with?(root == "/" ? "/" : "#{root}/") }
      end
    end
  end
end
