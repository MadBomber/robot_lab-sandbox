# Troubleshooting

## Interpreter installed under `$HOME` is invisible

**Symptom:** a script fails as soon as it invokes its interpreter, with
something like `ruby: Operation not permitted` (exit 126, e.g. an rbenv shim)
or `Killed: 9` (exit 137, a compiled binary), but the same script runs fine
with `sandbox.enabled: false`.

**Cause:** the generated Seatbelt profile never grants read access to
`$HOME`, on purpose — that's what keeps SSH keys and cloud credentials out of
reach of a confined script. But it also means any interpreter installed
under `$HOME` (rbenv, asdf, mise, a Homebrew prefix under `~`, `~/.gem`, a
project-local `bundle` path under `~/.bundle`) is unreadable to the sandboxed
process. The skill script itself still starts — `ScriptTool` always runs it
as `bash <script>`, ignoring its shebang — but the first command that lives
under `$HOME` cannot be loaded.

**Fix:** either

- Grant the interpreter's install path explicitly in the skill's `fs_read`:
  ```yaml
  fs_read: ["~/.rbenv"]
  ```
  (this still goes through the config `sandbox.fs_read` ceiling — the
  ceiling must permit it too, see [Configuration](configuration.md#the-intersection)), or
- Mark the skill `trust: core` if you wrote and audited it yourself — this
  bypasses confinement entirely, see [Configuration — trust: core](configuration.md#trust-core-bypassing-confinement).

## A path I granted is still denied

**Symptom:** a script writes to (or reads from) a path you declared in
`fs_write`/`fs_read`, but the write or read fails with `Operation not permitted`
(or comes back empty if the script discards errors), even though `sandbox.enabled: true` and the skill's front matter
looks right.

**Checklist:**

1. **Is the path inside the config ceiling?** The effective grant is the
   *intersection* of what the skill declares and `config.sandbox.fs_read`/
   `fs_write` — a path outside every ceiling root is dropped silently, even
   if the skill asks for it. Check `RobotLab::Sandbox::Ceiling.build.fs_read`
   / `.fs_write` in a console.
2. **Is it a symlinked path?** macOS symlinks `/tmp` → `/private/tmp`,
   `/var` → `/private/var`. The profile is generated against the resolved
   real path — if you're comparing against the logical path elsewhere (e.g.
   in a test assertion), resolve it with `File.realpath` first. See
   [How It Works — Path canonicalization](how_it_works.md#path-canonicalization).
3. **Does the path leave the ceiling through a symlink?** A granted path is
   kept only when its *real* location is inside a real ceiling root. A
   symlink under the working directory that points somewhere else is
   dropped, and so is a symlink loop or a dangling symlink. Grant the real
   target, and make sure the ceiling covers it.
4. **Does the path exist yet, for a write target?** Canonicalization walks up
   to the nearest existing ancestor to resolve symlinks, then re-appends the
   rest — if an intermediate directory is later created as a symlink, the
   kernel resolves it and the write lands outside the granted path, so it
   is denied. Prefer granting an existing parent directory over a
   not-yet-created nested path.
5. **Is `trust: core` set?** A `core` skill bypasses the sandbox entirely —
   if you're debugging a *denial* and the skill is `trust: core`, the
   sandbox isn't involved at all; look elsewhere (permissions, the script
   itself).

You can inspect the exact profile a skill's declaration produces without
running anything:

```ruby
declared = RobotLab::Capabilities.new(fs_read: ["./data"], fs_write: ["./out"])
grant    = RobotLab::Sandbox::Grant.resolve(declared, RobotLab::Sandbox::Ceiling.build)
puts RobotLab::Sandbox::Seatbelt.new(grant, skill_dir: "./skills/example").profile_text
```

## Nothing is confined, even with `sandbox.enabled: true`

**Symptom:** scripts still behave as if sandboxing were off — no denials,
no warnings, everything just works as before.

**Checklist:**

1. **Is `RobotLab::Sandbox.enabled?` actually true?** Check it in a console
   rather than trusting the config file — it is the exact test the executor
   uses. `true`/`1`/`yes`/`on` (as a boolean or an env-var string) turn it
   on; `false`/`0`/`no`/`off`, empty, or unset leave it off.
2. **Is `robot_lab/sandbox` actually required?** `require "robot_lab/sandbox"`
   must run *after* `require "robot_lab"`. Check:
   ```ruby
   RobotLab::ScriptTool.executor  # nil means this gem was never loaded
   ```
3. **Is the skill `trust: core`?** Always bypasses confinement — see above.
4. **Are you off macOS?** Confinement is macOS-only; elsewhere every script
   runs through `Sandbox::Null` (a passthrough) with a one-time warning
   logged (`Sandbox: OS-level confinement is only available on macOS; ...`).
   Check `RobotLab::Sandbox.macos?`.

## A script that used to finish now gets killed with `[killed: exceeded Ns]`

**Cause:** once this gem is loaded and sandboxing is enabled, every script
run is bounded by the effective grant's `timeout` — the smaller of the
skill's declared `timeout:` and `config.sandbox.timeout` (default `60`).
Core alone never enforced a timeout at all, so a slow script that worked
fine before can now hit this for the first time.

The bound covers the whole run, not just its output: on expiry the script's
process group gets `SIGTERM`, then `SIGKILL` two seconds later if anything
is still alive. What the script printed before the kill is returned ahead of
the `[killed: exceeded Ns]` marker. A process that leaves the group
(`setsid`) is not reached by the kill, though it stays inside the Seatbelt
profile.

**Fix:** raise the skill's declared `timeout:` in its `SKILL.md` front
matter, and/or raise the config ceiling's `sandbox.timeout` — whichever is
currently the smaller (and therefore binding) value.

## `robot_lab/sandbox` raises on require

```
RobotLab::Sandbox::Error: robot_lab must be loaded before robot_lab/sandbox
```

**Cause:** `require "robot_lab/sandbox"` ran before `require "robot_lab"` (or
`robot_lab` failed to load for some other reason first). `robot_lab/sandbox`
checks `defined?(RobotLab::ScriptTool)` at load time and raises immediately
rather than silently no-op-ing, since a sandbox gem that failed to install
itself and said nothing would be far more dangerous than one that's loud
about it.

**Fix:** reorder your `require`s (or Gemfile-driven autoload order) so
`robot_lab` loads first.
