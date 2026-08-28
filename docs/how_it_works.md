# How It Works

## The Extension Point: `ScriptTool.executor`

`robot_lab` core's `RobotLab::ScriptTool` exposes a single seam for
confinement:

```ruby
module RobotLab
  module ScriptTool
    class << self
      attr_accessor :executor
    end
  end
end
```

`executor` is `nil` by default. `ScriptTool.execute(cmd, capabilities:, skill_dir:)`
checks it on every call:

```ruby
def self.execute(cmd, capabilities:, skill_dir:)
  return executor.call(cmd, capabilities: capabilities, skill_dir: skill_dir) if executor

  output, status = Open3.capture2e(*cmd)
  format_result(output, status)
end
```

### `ScriptTool.execute` with no executor installed

Without `robot_lab-sandbox` (or any other gem setting `executor`), every call
takes the second branch: a plain `Open3.capture2e`, unconfined, with no
timeout. This is exactly how core alone always behaved — the extension point
was added specifically so this default stays true with zero code in core
that knows anything about sandboxing.

### What loading this gem does

`lib/robot_lab/sandbox.rb` runs this at load time:

```ruby
unless defined?(RobotLab::ScriptTool)
  raise RobotLab::Sandbox::Error, "robot_lab must be loaded before robot_lab/sandbox"
end

RobotLab::ScriptTool.executor = RobotLab::Sandbox::Executor

if RobotLab.respond_to?(:register_extension)
  RobotLab.register_extension(:sandbox, RobotLab::Sandbox)
end
```

From that point on, every `ScriptTool.execute` call delegates entirely to
`RobotLab::Sandbox::Executor.call`. Core no longer knows or cares what the
executor does with `capabilities` or how — or whether — it bounds execution
time; that's this gem's job from here down.

## `Sandbox::Executor` — What Actually Runs

```ruby
def self.call(cmd, capabilities:, skill_dir:)
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
```

Two paths, gated by `Sandbox.enabled?` (which reads `config.sandbox.enabled`,
default `false`):

1. **Disabled** — identical to core's own unconfined path. Loading this gem
   with `sandbox.enabled: false` changes nothing observable.
2. **Enabled** — computes the effective grant (skill's declared `Capabilities`
   ∩ the config ceiling, see [Configuration](configuration.md#the-intersection)),
   picks a strategy via `Sandbox.for`, wraps the command, runs it under a
   timeout, and always calls `sandbox.cleanup` in an `ensure` — even if the
   run raised or timed out.

## Strategy Selection: `Sandbox.for`

```ruby
def self.for(grant, skill_dir:, macos: macos?)
  return Null.new if grant.core?
  return Seatbelt.new(grant, skill_dir: skill_dir) if macos

  warn_once_non_macos
  Null.new
end
```

Selection order:

1. `trust: core` (`grant.core?`) → always `Sandbox::Null`, on every platform.
2. macOS → `Sandbox::Seatbelt`.
3. Anything else → `Sandbox::Null`, plus a one-time `warn`-level log message
   (`Sandbox.warn_once_non_macos`, idempotent — a run with many scripts
   doesn't flood the log).

`macos:` is injectable (defaults to the real `RUBY_PLATFORM` check) so both
branches are testable on any host without stubbing.

## `Sandbox::Null` — the Passthrough

```ruby
class Null
  def wrap(cmd) = cmd
  def cleanup; end
end
```

`wrap` is the identity function; `cleanup` is a no-op. Used off-macOS and for
`trust: core` skills — the command runs exactly as it would with no executor
installed at all, except still bounded by `Executor`'s timeout.

## `Sandbox::Seatbelt` — Real Confinement on macOS

`wrap(cmd)` generates a Seatbelt profile to a `Tempfile` and returns:

```ruby
["sandbox-exec", "-f", profile_path, *cmd]
```

### The generated profile

```
(version 1)
(import "bsd.sb")
(deny default)
(allow process-fork)
(allow process-exec)
(allow sysctl-read)
(allow mach-lookup)
(allow file-read-metadata)
(allow file-read* (subpath "/usr") (subpath "/bin") ... (subpath <skill_dir>) (subpath <granted fs_read>) ...)
(allow file-write* (literal "/dev/null") ... (subpath <granted fs_write>))
(allow network*)   ; only present when the grant allows network
```

Built from three pieces:

| Piece | Source |
|-------|--------|
| **Deny by default** | `(deny default)` — nothing is allowed unless an explicit `(allow ...)` clause says so. |
| **Boot allowances** | `(import "bsd.sb")` (the base rules a process needs to start — dyld, mach bootstrap, etc.; without it a deny-default profile aborts the binary before it runs), plus `process-fork`, `process-exec`, `sysctl-read`, `mach-lookup`, and `file-read-metadata` on any path (so the interpreter can `stat`/traverse to reach granted files — reading file *contents* stays restricted separately). |
| **The grant** | `file-read*` on `Seatbelt::SYSTEM_READ` (`/usr /bin /sbin /System /Library /opt /private/etc /dev /var/select`) plus the skill directory plus the grant's `fs_read`; `file-write*` on `Seatbelt::DEV_WRITE` (`/dev/null /dev/stdout /dev/stderr /dev/dtracehelper /dev/tty`) plus the grant's `fs_write`; `network*` only when `grant.network` is true. |

`$HOME` is never in any of these lists — it is never implicitly readable.
See [Troubleshooting](troubleshooting.md#interpreter-installed-under-home-is-invisible)
for the direct consequence of that.

### Path canonicalization

Every path is resolved to its symlink-free real path before being written
into the profile:

```ruby
def canonicalize(paths)
  Array(paths).map { |p| real_path(File.expand_path(p.to_s)) }.compact.uniq
end
```

This matters because macOS symlinks `/tmp` → `/private/tmp`, `/var` →
`/private/var`, etc. — the kernel matches Seatbelt rules against the *real*
path, so a rule written against the logical `/tmp/...` path would silently
never match. For a write target that doesn't exist yet, `real_path` walks up
to the nearest existing ancestor, resolves *that*, and re-appends the
non-existent remainder.

### Lifecycle

`wrap` writes the profile via `Tempfile.create`; `cleanup` unlinks it and
swallows any error (an already-removed file is fine). `Executor.call` always
calls `sandbox.cleanup` in an `ensure`, so a profile file is never leaked
even when the script raises or times out.

## Timeout Enforcement

`Executor.run_with_timeout(cmd, timeout)` runs the (possibly Seatbelt-wrapped)
command in its own process group and reads combined stdout+stderr until
`timeout` seconds elapse:

```ruby
def self.run_with_timeout(cmd, timeout)
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
```

On expiry, `terminate` sends `SIGTERM` to the whole process **group**
(`Process.kill('-TERM', ...)` against `Process.getpgid(pid)`), so a script
that spawned children takes them down with it, and swallows any error — a
process that already exited by the time `terminate` runs is not an error. A
`nil` status return value is `ScriptTool.format_result`'s signal for
`"Error (timed out):\n<output>"`, which is what the LLM sees; a `nil`
status is never confused with a real (even nonzero) exit code.

The timeout used is `grant.timeout` — the smaller of the skill's declared
`timeout:` and the config ceiling's `sandbox.timeout` (see
[Configuration](configuration.md#the-intersection)). This bound applies only
because this gem is loaded; core alone never times a script out.

## Extension Registration

`RobotLab.register_extension(:sandbox, RobotLab::Sandbox)` lets other code
detect this gem is loaded without depending on it directly:

```ruby
RobotLab.extension_loaded?(:sandbox)  # => true, once required
RobotLab.extension(:sandbox)          # => RobotLab::Sandbox, or nil
```

This follows the same pattern every other RobotLab extension gem
(`robot_lab-audit`, `robot_lab-durable`, etc.) uses — `register_extension` is
a no-op-safe check (`RobotLab.respond_to?(:register_extension)`), so
`robot_lab/sandbox` never raises on this line even against an unusually old
`robot_lab` core.
