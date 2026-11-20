# frozen_string_literal: true

module RobotLab
  module Sandbox
    # Normalizes raw `config.sandbox.*` values before this gem acts on them.
    #
    # Values set through ROBOT_LAB_SANDBOX__* environment variables arrive as
    # Strings ("true", "false", "30", "./tmp,./out"), not as the booleans,
    # integers, and arrays the YAML defaults carry. Treating those strings by
    # Ruby truthiness would read "false" as true, so every value this gem reads
    # is coerced here first. Anything unrecognized takes the more restrictive
    # reading.
    module Coerce
      TRUE_WORDS  = %w[true 1 yes on y t].freeze
      FALSE_WORDS = ["false", "0", "no", "off", "n", "f", ""].freeze

      module_function

      # @param value [Object] raw config value
      # @param ambiguous [Boolean] result for a value that is neither a
      #   recognized "on" nor a recognized "off" word
      # @return [Boolean]
      # :reek:BooleanParameter -- `ambiguous` is the caller's fail-safe answer, not a mode switch.
      # :reek:ControlParameter -- same: it is returned, never branched on.
      def truthy?(value, ambiguous:)
        return false if value.nil?

        text = value.to_s.strip.downcase
        return true  if TRUE_WORDS.include?(text)
        return false if FALSE_WORDS.include?(text)

        ambiguous ? true : false
      end

      # @param value [Object] an Array of paths, or a comma-separated String
      # @param default [Array<String>] used only when the value is nil
      # @return [Array<String>]
      def paths(value, default)
        return default if value.nil?

        entries = value.is_a?(String) ? value.split(",") : Array(value)
        entries.map { |entry| entry.to_s.strip }.reject(&:empty?)
      end

      # @param value [Object] seconds
      # @return [Integer] a positive whole number of seconds; anything that is
      #   not one (nil, true, a list, "abc", 0, a negative) becomes the default
      def timeout(value)
        seconds = Integer(value, exception: false)
        seconds&.positive? ? seconds : Capabilities::DEFAULT_TIMEOUT
      end

      # Like {timeout}, but keeps a usable fractional bound as-is.
      #
      # @param value [Object] seconds
      # @return [Numeric] a positive, finite number of seconds
      def duration(value)
        return value if value.is_a?(Numeric) && value.finite? && value.positive?

        timeout(value)
      end
    end
  end
end
