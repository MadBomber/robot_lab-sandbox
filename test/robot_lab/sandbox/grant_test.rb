# frozen_string_literal: true

require "test_helper"
require "fileutils"

module RobotLab
  module Sandbox
    class GrantTest < Minitest::Test
      # work/data is real; work/link is a symlink to a directory outside work.
      def with_tree
        Dir.mktmpdir do |base|
          base    = File.realpath(base)
          work    = File.join(base, "work")
          outside = File.join(base, "outside")
          FileUtils.mkdir_p([File.join(work, "data"), outside])
          File.write(File.join(work, "data", "d.txt"), "DATA\n")
          File.write(File.join(outside, "secret.txt"), "TOPSECRET\n")
          File.symlink(outside, File.join(work, "link"))
          yield work, outside
        end
      end

      def with_sandbox_config(**values)
        section = RobotLab.config.sandbox
        saved   = values.keys.to_h { |key| [key, section.public_send(key)] }
        values.each { |key, value| section.public_send("#{key}=", value) }
        yield
      ensure
        saved.each { |key, value| section.public_send("#{key}=", value) }
      end

      def run_confined(script, capabilities, skill_dir)
        Executor.call(["bash", "-c", script], capabilities: capabilities, skill_dir: skill_dir)
      end

      # --- Paths ---

      def test_real_resolves_symlinks_and_missing_tails
        with_tree do |work, outside|
          assert_equal outside, Paths.real(File.join(work, "link"))
          assert_equal File.join(outside, "new", "file"), Paths.real(File.join(work, "link", "new", "file"))
          assert_equal File.join(work, "data"), Paths.real(File.join(work, "data"))
        end
      end

      def test_real_returns_nil_when_unresolvable
        Dir.mktmpdir do |dir|
          loop_link = File.join(dir, "loop")
          File.symlink(loop_link, loop_link)
          assert_nil Paths.real(File.join(loop_link, "x"))

          dangling = File.join(dir, "dangling")
          File.symlink(File.join(dir, "missing"), dangling)
          assert_nil Paths.real(dangling)
        end
      end

      def test_inside_matches_roots_and_descendants_only
        assert Paths.inside?("/a/b", ["/a/b"])
        assert Paths.inside?("/a/b/c", ["/x", "/a/b"])
        refute Paths.inside?("/a/bc", ["/a/b"])
        refute Paths.inside?("/a", ["/a/b"])
        refute Paths.inside?("/a/b", [])
        assert Paths.inside?("/anything", ["/"])
      end

      # --- Grant ---

      def test_confine_drops_symlink_that_leaves_the_ceiling
        with_tree do |work, _outside|
          kept = Grant.confine([File.join(work, "data"), File.join(work, "link")], [work])
          assert_equal [File.join(work, "data")], kept
        end
      end

      def test_confine_drops_paths_that_cannot_be_resolved
        Dir.mktmpdir do |dir|
          dir       = File.realpath(dir)
          loop_link = File.join(dir, "loop")
          File.symlink(loop_link, loop_link)
          assert_equal [], Grant.confine([File.join(loop_link, "x")], [dir])
          assert_equal [], Grant.confine([dir], [File.join(loop_link, "x")])
        end
      end

      def test_resolve_keeps_lexical_rules_and_resolves_paths
        with_tree do |work, outside|
          declared = Capabilities.new(
            fs_read: [File.join(work, "data"), File.join(work, "link"), outside],
            fs_write: [File.join(work, "link", "w")], network: true, timeout: 5, trust: "core"
          )
          ceiling = Capabilities.new(fs_read: [work], fs_write: [work], network: false, timeout: 9)
          grant   = Grant.resolve(declared, ceiling)

          assert_equal [File.join(work, "data")], grant.fs_read
          assert_equal [], grant.fs_write
          refute grant.network
          assert_equal 5, grant.timeout
          assert grant.core?
        end
      end

      def test_resolve_accepts_a_ceiling_that_is_itself_behind_a_symlink
        with_tree do |work, _outside|
          Dir.mktmpdir do |other|
            alias_root = File.join(File.realpath(other), "alias")
            File.symlink(work, alias_root)
            declared = Capabilities.new(fs_read: [File.join(alias_root, "data")])
            grant    = Grant.resolve(declared, Capabilities.new(fs_read: [alias_root]))
            assert_equal [File.join(work, "data")], grant.fs_read
          end
        end
      end

      # --- real confinement (macOS only) ---

      def test_symlink_inside_ceiling_cannot_read_or_write_outside
        skip "Seatbelt is macOS-only" unless Sandbox.macos?

        with_tree do |work, outside|
          link = File.join(work, "link")
          caps = Capabilities.new(fs_read: [File.join(work, "data"), link], fs_write: [link], timeout: 10)
          with_sandbox_config(enabled: true, fs_read: [work], fs_write: [work]) do
            assert_includes run_confined("cat #{work}/data/d.txt", caps, work), "DATA"

            read = run_confined("cat #{outside}/secret.txt", caps, File.join(work, "data"))
            refute_includes read, "TOPSECRET"
            assert_includes read, "Operation not permitted"

            run_confined("echo x > #{outside}/written", caps, File.join(work, "data"))
            refute File.exist?(File.join(outside, "written"))
          end
        end
      end

      def test_env_string_network_false_ceiling_blocks_network
        skip "Seatbelt is macOS-only" unless Sandbox.macos?
        require "socket"

        server = TCPServer.new("127.0.0.1", 0)
        port   = server.addr[1]
        caps   = Capabilities.new(network: true, timeout: 10)
        script = "(exec 3<>/dev/tcp/127.0.0.1/#{port}) 2>&1 && echo CONNECTED"
        Dir.mktmpdir do |dir|
          with_sandbox_config(enabled: "true", network: "false") do
            refute_includes run_confined(script, caps, dir), "CONNECTED"
          end
          with_sandbox_config(enabled: "true", network: "true") do
            assert_includes run_confined(script, caps, dir), "CONNECTED"
          end
        end
      ensure
        server&.close
      end
    end
  end
end
