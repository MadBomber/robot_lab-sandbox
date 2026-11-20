# frozen_string_literal: true

require "test_helper"

module RobotLab
  module Sandbox
    class CoerceTest < Minitest::Test
      def test_truthy_recognizes_on_words
        [true, "true", "TRUE", " yes ", "1", 1, "on", "y", "t"].each do |value|
          assert Coerce.truthy?(value, ambiguous: false), value.inspect
        end
      end

      def test_truthy_recognizes_off_words_even_when_ambiguous_is_true
        [false, nil, "false", "False", "0", 0, "no", "off", "n", "f", "", "  "].each do |value|
          refute Coerce.truthy?(value, ambiguous: true), value.inspect
        end
      end

      def test_truthy_returns_the_fail_safe_answer_for_unrecognized_values
        assert_equal true,  Coerce.truthy?("maybe", ambiguous: true)
        assert_equal false, Coerce.truthy?("maybe", ambiguous: false)
        assert_equal false, Coerce.truthy?(["true"], ambiguous: false)
      end

      def test_paths_splits_a_comma_separated_string
        assert_equal %w[./tmp ./out], Coerce.paths("./tmp, ./out,", [])
        assert_equal [], Coerce.paths("", ["."])
      end

      def test_paths_keeps_arrays_and_defaults_only_nil
        assert_equal ["a,b", "c"], Coerce.paths(["a,b", :c, " "], [])
        assert_equal ["."], Coerce.paths(nil, ["."])
        assert_equal [], Coerce.paths([], ["."])
      end

      def test_timeout_accepts_positive_whole_seconds
        assert_equal 30, Coerce.timeout(30)
        assert_equal 30, Coerce.timeout("30")
        assert_equal 2,  Coerce.timeout(2.9)
      end

      def test_timeout_falls_back_to_default_for_malformed_values
        [nil, true, [5], { a: 1 }, "abc", "", 0, -3, 0.2, Float::INFINITY, Float::NAN].each do |value|
          assert_equal Capabilities::DEFAULT_TIMEOUT, Coerce.timeout(value), value.inspect
        end
      end

      def test_duration_keeps_fractions_but_not_malformed_values
        assert_in_delta 0.2, Coerce.duration(0.2)
        assert_equal 5, Coerce.duration(5)
        [nil, true, [5], "abc", 0, -1.5, Float::INFINITY, Float::NAN].each do |value|
          assert_equal Capabilities::DEFAULT_TIMEOUT, Coerce.duration(value), value.inspect
        end
      end
    end
  end
end
