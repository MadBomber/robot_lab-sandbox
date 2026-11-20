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
module_function

def call(cmd, capabilities:, skill_dir:)
  unless Sandbox.enabled?
    output, status = Open3.capture2e(*cmd)
    return RobotLab::ScriptTool.format_result(output, status)
  end

  grant   = Grant.resolve(capabilities, Ceiling.build)
  sandbox = Sandbox.for(grant, skill_dir: skill_dir)
  begin
    output, status = run_with_timeout(sandbox.wrap(cmd), grant.timeout)
    format_result(output, status)
  ensure
    sandbox.cleanup
  end
end
```

Two paths, gated by `Sandbox.enabled?` (which reads `config.sandbox.enabled`,
default `false`, accepting the string forms an environment variable
delivers — see [Configuration](configuration.md#the-sandbox-ceiling)):

1. **Disabled** — identical to core's own unconfined path. Loading this gem
   with `sandbox.enabled: false` changes nothing observable.
2. **Enabled** — computes the effective grant (skill's declared `Capabilities`
   ∩ the config ceiling, see [Configuration](configuration.md#the-intersection)),
   picks a strategy via `Sandbox.for`, wraps the command, runs it under a
   timeout, and always calls `sandbox.cleanup` in an `ensure` — even if the
   run raised or timed out. `Executor.format_result` is core's
   `ScriptTool.format_result` plus one case: a process that died from a
   signal is reported as `"Error (killed by signal N):\n<output>"`.

## Strategy Selection: `Sandbox.for`

```ruby
module_function

def for(grant, skill_dir:, macos: macos?)
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
The exceptions are the skill directory itself (always granted, even when it
lives under `$HOME`), file *metadata* (`file-read-metadata` is allowed on
every path, so a confined script can `stat` any file but not read or list
it), and whatever `bsd.sb` itself allows (e.g. `.CFUserTextEncoding`).
See [Troubleshooting](troubleshooting.md#interpreter-installed-under-home-is-invisible)
for the direct consequence of that.

### Path canonicalization

Every path is resolved to its symlink-free real path before being written
into the profile:

```ruby
def canonicalize(paths)
  Array(paths).filter_map { |p| Paths.real(p) }.uniq
end
```

This matters because macOS symlinks `/tmp` → `/private/tmp`, `/var` →
`/private/var`, etc. — the kernel matches Seatbelt rules against the *real*
path, so a rule written against the logical `/tmp/...` path would silently
never match. For a write target that doesn't exist yet, `Paths.real` walks up
to the nearest existing ancestor, resolves *that*, and re-appends the
non-existent remainder. A path that cannot be resolved (a symlink loop, a
dangling symlink) yields `nil` and is left out of the profile.

The same resolution guards the grant itself: `Grant.resolve` only keeps a
declared path whose *real* location is inside a real ceiling root, so a
symlink under the ceiling that points elsewhere is dropped before a profile
is ever generated (see [Configuration](configuration.md#the-intersection)).

### Lifecycle

`wrap` writes the profile via `Tempfile.create`; `cleanup` unlinks it and
swallows any error (an already-removed file is fine). `Executor.call` always
calls `sandbox.cleanup` in an `ensure`, so a profile file is never leaked
even when the script raises or times out.

## Timeout Enforcement

`Executor.run_with_timeout(cmd, timeout)` runs the (possibly Seatbelt-wrapped)
command in its own process group and bounds the **whole execution** — the
process itself, not just its output — at `timeout` seconds:

```ruby
module_function

def run_with_timeout(cmd, timeout)
  limit = Coerce.duration(timeout)
  Open3.popen2e(child_env, *cmd, pgroup: true) do |stdin, out, wait|
    stdin.close
    supervise(out, wait, limit)
  end
end

def supervise(out, wait, limit)
  buffer = +""
  reader = Thread.new { drain(out, buffer) }
  return [text(buffer), wait.value] if finished_within?(limit, wait, reader)

  terminate(wait.pid)
  reader.join(POLL)
  reader.kill
  ["#{text(buffer)}\n[killed: exceeded #{limit}s]", nil]
end
```

A reader thread drains combined stdout+stderr into a buffer while
`finished_within?` waits on the process. The run counts as finished only when
the process has exited **and** its output has reached EOF inside the limit,
so neither a script that closes its output and keeps running nor a
background child left holding the pipe escapes the bound.

On expiry, `terminate` sends `SIGTERM` to the whole process **group**
(`Process.kill("TERM", -pid)` — `pgroup: true` makes the child its own group
leader), so a script that spawned children takes them down with it. Anything
still alive after `Executor::KILL_GRACE` (2 seconds) gets `SIGKILL`.
`terminate` never raises — a group that is already gone is not an error —
and refuses a pid of 1 or less. A process that leaves the group (`setsid`)
is not reached by the kill; it remains inside the Seatbelt profile.

A `nil` status return value is `ScriptTool.format_result`'s signal for
`"Error (timed out):\n<output>"`, which is what the LLM sees; a `nil`
status is never confused with a real (even nonzero) exit code. `<output>` is
whatever the script printed before the kill, followed by
`"\n[killed: exceeded <timeout>s]"`.

`Coerce.duration` keeps any positive, finite number and replaces anything
else (`nil`, `true`, a list, a non-numeric string, zero or a negative) with
the 60-second default, so a malformed timeout cannot crash the executor.
`child_env` passes the real working directory as `PWD`: without it the shell
calls `getcwd()`, which fails under Seatbelt because the working directory's
ancestors are not readable, and prints a `shell-init: error retrieving
current directory` line into the output. It grants no access.

The timeout used is `grant.timeout` — the smaller of the skill's declared
`timeout:` and the config ceiling's `sandbox.timeout` (see
[Configuration](configuration.md#the-intersection)). This bound applies only
when this gem is loaded and sandboxing is enabled; core alone (or this gem
with `sandbox.enabled: false`) never times a script out.

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
