# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Gem Does

`robot_lab-sandbox` provides OS-level confinement for RobotLab AgentSkills scripts. It was extracted from `robot_lab` core so that core has **no built-in limitations**: every skill script runs unconfined unless an application explicitly requires `robot_lab-sandbox`.

## Commands

```bash
bundle exec rake test        # Run full test suite
ruby -Ilib:test test/<file>  # Run a single test file
bundle exec rake quality     # Tests + coverage + RuboCop + Flog + Flay

bin/console                  # IRB session with gem loaded
```

## Enabling

```ruby
require "robot_lab"
require "robot_lab/sandbox"
# RobotLab::ScriptTool.executor is now RobotLab::Sandbox::Executor.
# Confinement itself still only activates when config.sandbox.enabled is true
# (see robot_lab core's config/defaults.yml `sandbox:` section) -- requiring
# this gem alone does not change behavior until that flag is set.
```

## Architecture

All source lives under `lib/robot_lab/sandbox/`, in the `RobotLab::Sandbox` namespace (same namespace it used inside `robot_lab` core before extraction).

**`Sandbox`** (`sandbox.rb`) — Dispatcher. `Sandbox.enabled?` reads `RobotLab.config.sandbox.enabled`. `Sandbox.for(grant, skill_dir:)` picks a strategy: `Seatbelt` on macOS, `Null` elsewhere or for `trust: core` skills. On load, this file requires the strategies and `Executor`, then installs `RobotLab::Sandbox::Executor` as `RobotLab::ScriptTool.executor` and registers itself via `RobotLab.register_extension(:sandbox, RobotLab::Sandbox)`. Raises `Sandbox::Error` if `robot_lab` was not loaded first.

**`Sandbox::Seatbelt`** (`sandbox/seatbelt.rb`) — macOS strategy. Generates a deny-by-default `sandbox-exec` profile from the effective grant (system read paths + skill dir + granted `fs_read`; granted `fs_write` + `/dev` sinks; network only if granted) and wraps the command as `sandbox-exec -f <profile> <cmd...>`. Canonicalizes symlinked paths (e.g. `/tmp` → `/private/tmp`) so the kernel's rules actually match.

**`Sandbox::Null`** (`sandbox/null.rb`) — Passthrough strategy; `wrap` is the identity, `cleanup` is a no-op.

**`Sandbox::Executor`** (`sandbox/executor.rb`) — The integration point installed as `RobotLab::ScriptTool.executor`. When sandboxing is disabled, runs the command unconfined via `Open3.capture2e` with no timeout (identical to core's own behavior with no executor installed). When enabled, intersects the skill's declared `Capabilities` with `Capabilities.ceiling` (from `robot_lab` core), wraps the command with the chosen `Sandbox` strategy, and bounds execution with `Timeout` at the grant's `timeout` value, killing the process group on expiry.

`RobotLab::Capabilities` itself — the declarative fs_read/fs_write/network/timeout/trust manifest parsed from a skill's `SKILL.md` front matter — stays in `robot_lab` core, since `AgentSkill` needs to build it regardless of whether this gem is loaded. This gem only adds *enforcement*.

## Key Constraints

- `robot_lab` must be loaded before `robot_lab/sandbox` — `sandbox.rb` raises `Sandbox::Error` otherwise.
- Confinement is macOS-only. Off-macOS (or for `trust: core` skills) this gem still installs the executor, but every run goes through `Sandbox::Null` — a warning is logged once per process on non-macOS.
- Sandboxing stays opt-in via `config.sandbox.enabled` (default `false`, declared in `robot_lab` core's `config/defaults.yml`) — requiring this gem does not itself turn confinement on.
- The generated Seatbelt profile never implicitly allows reading `$HOME` — interpreters installed under `$HOME` (e.g. rbenv) need an explicit `fs_read` grant or `trust: core`.

## Testing

- Minitest with SimpleCov (branch coverage tracked)
- The real Seatbelt-confinement integration test in `test/robot_lab/sandbox_test.rb` (`test_seatbelt_confines_execution`) only runs on macOS; it is skipped elsewhere
- `test/robot_lab/sandbox/executor_test.rb` covers `Executor.call`, `run_with_timeout`, and `terminate`
