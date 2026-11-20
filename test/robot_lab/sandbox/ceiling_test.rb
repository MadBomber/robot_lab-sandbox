# frozen_string_literal: true

require "test_helper"

module RobotLab
  module Sandbox
    class CeilingTest < Minitest::Test
      Section = Struct.new(:fs_read, :fs_write, :network, :timeout)
      Config  = Struct.new(:sandbox)

      def ceiling(**values)
        Ceiling.build(Config.new(Section.new(*values.values_at(:fs_read, :fs_write, :network, :timeout))))
      end

      def test_defaults_when_values_are_unset
        c = ceiling
        assert_equal ["."], c.fs_read
        assert_equal [], c.fs_write
        refute c.network
        assert_equal Capabilities::DEFAULT_TIMEOUT, c.timeout
      end

      def test_defaults_when_config_has_no_sandbox_section
        [Object.new, Config.new(nil)].each do |config|
          c = Ceiling.build(config)
          assert_equal ["."], c.fs_read
          assert_equal [], c.fs_write
          refute c.network
        end
      end

      # ROBOT_LAB_SANDBOX__NETWORK=false arrives as the String "false", which
      # core's Capabilities.ceiling reads as truthy.
      def test_env_string_false_does_not_grant_network
        refute ceiling(network: "false").network
        refute ceiling(network: "0").network
        refute ceiling(network: "").network
      end

      def test_ambiguous_network_value_is_denied
        refute ceiling(network: "sometimes").network
      end

      def test_env_string_true_grants_network
        assert ceiling(network: "true").network
        assert ceiling(network: true).network
      end

      def test_comma_separated_env_paths_become_separate_roots
        c = ceiling(fs_read: ".,./data", fs_write: "./tmp,./out")
        assert_equal %w[. ./data], c.fs_read
        assert_equal %w[./tmp ./out], c.fs_write
      end

      def test_env_string_and_malformed_timeouts
        assert_equal 30, ceiling(timeout: "30").timeout
        assert_equal Capabilities::DEFAULT_TIMEOUT, ceiling(timeout: true).timeout
        assert_equal Capabilities::DEFAULT_TIMEOUT, ceiling(timeout: [5]).timeout
      end

      def test_real_config_ceiling
        c = Ceiling.build
        assert_equal ["."], c.fs_read
        assert_equal [], c.fs_write
        refute c.network
      end
    end
  end
end
