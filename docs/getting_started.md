# Getting Started

## Prerequisites

- Ruby 3.2+ (per the gemspec's `required_ruby_version`)
- `robot_lab` — `robot_lab/sandbox` requires `RobotLab::ScriptTool` to already
  be defined, so `robot_lab` must be `require`d first.
- macOS, if you want real OS-level confinement. On other platforms the gem
  still loads and wires itself in, but every script runs through
  `Sandbox::Null` (a passthrough) with a one-time warning logged.

## Installation

Add to your `Gemfile`:

```ruby
gem "robot_lab"
gem "robot_lab-sandbox"
```

Then:

```sh
bundle install
```

Or install directly:

```sh
gem install robot_lab-sandbox
```

## Enabling

Requiring the gem and turning on confinement are two separate steps —
matching how `robot_lab` core's `sandbox:` config section already worked
before this gem existed.

**1. Require it**, after `robot_lab`:

```ruby
require "robot_lab"
require "robot_lab/sandbox"
```

This installs `RobotLab::Sandbox::Executor` as `RobotLab::ScriptTool.executor`
and registers the gem via `RobotLab.register_extension(:sandbox, ...)`. On its
own this changes nothing yet — see [How It Works](how_it_works.md#scripttoolexecute-with-no-executor-installed)
for why: `ScriptTool.execute` only delegates to the executor when one is
installed, and the executor itself checks `Sandbox.enabled?` before doing
anything.

**2. Turn on confinement** in config:

```yaml
# config/robot_lab.yml
sandbox:
  enabled: true
  fs_read: ["."]
  fs_write: []
  network: false
  timeout: 60
```

or via environment variables:

```sh
export ROBOT_LAB_SANDBOX__ENABLED=true
```

If `robot_lab` has not been loaded yet, `require "robot_lab/sandbox"` raises
`RobotLab::Sandbox::Error` ("robot_lab must be loaded before robot_lab/sandbox").

## Minimal Example

```ruby
require "robot_lab"
require "robot_lab/sandbox"

RobotLab.config.sandbox.enabled = true
RobotLab.config.sandbox.fs_write = ["./tmp"]

# A skill's SKILL.md declares what it wants; robot_lab core builds the
# Capabilities object from that front matter automatically when the skill
# is discovered. Here we build one directly to call ScriptTool ourselves:
capabilities = RobotLab::Capabilities.new(fs_write: ["./tmp"], timeout: 10)

tool = RobotLab::ScriptTool.from_path(
  "./skills/cleanup/scripts/purge_tmp.sh",
  capabilities: capabilities,
  skill_dir: "./skills/cleanup"
)

puts tool.call({}) # runs confined on macOS, unconfined (with a warning) elsewhere
```

In practice you won't call `ScriptTool.from_path` directly — a discovered
`AgentSkill` builds its own `script_tools` from its `SKILL.md` front matter
and capabilities automatically. This example exists to show the pieces in
isolation; see [robot_lab's Skill Scripts and Sandboxing guide](https://github.com/MadBomber/robot_lab/blob/main/docs/guides/using-tools.md#skill-scripts-and-sandboxing)
for the end-to-end skill-bundle path.

## Checking What's Installed

```ruby
RobotLab.extension_loaded?(:sandbox)   # => true, once required
RobotLab::ScriptTool.executor          # => RobotLab::Sandbox::Executor, or nil
RobotLab::Sandbox.enabled?             # => reads config.sandbox.enabled
RobotLab::Sandbox.macos?               # => RUBY_PLATFORM.include?("darwin")
```

## Key Constraints

- `robot_lab` must be `require`d before `robot_lab/sandbox` — see Prerequisites above.
- Confinement is opt-in via `config.sandbox.enabled` (default `false`).
  Requiring this gem does **not** turn confinement on by itself.
- Real OS-level confinement is macOS-only. Off macOS, or for any skill
  declaring `trust: core`, every script runs through the `Sandbox::Null`
  passthrough regardless of `sandbox.enabled`.
- The declared `timeout:` (per-skill or the config ceiling) only takes effect
  once this gem is loaded — core alone runs scripts with no timeout at all.
