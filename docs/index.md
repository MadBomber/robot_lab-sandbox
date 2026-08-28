# robot_lab-sandbox

OS-level confinement for [RobotLab](https://github.com/MadBomber/robot_lab) skill scripts.

`robot_lab` core has **no sandboxing and no execution limitations of its own** —
every [AgentSkill](https://github.com/MadBomber/robot_lab/blob/main/docs/api/skills.md)
script runs as a plain, unconfined OS process. `robot_lab-sandbox` plugs into
core's one extension point for this (`RobotLab::ScriptTool.executor`) and, once
turned on in config, confines each script to a declared, ceiling-clamped set of
capabilities: which paths it may read and write, whether it may reach the
network, and how long it may run.

```ruby
require "robot_lab"
require "robot_lab/sandbox"
# RobotLab::ScriptTool.executor is now RobotLab::Sandbox::Executor.
```

```yaml
# config/robot_lab.yml
sandbox:
  enabled: true
  fs_read: ["."]
  fs_write: ["./tmp"]
  network: false
  timeout: 60
```

On macOS, `enabled: true` wraps every skill script in a generated
deny-by-default `sandbox-exec` (Seatbelt) profile. Elsewhere it's a passthrough
with a one-time warning — confinement is currently macOS-only. Requiring the
gem never changes behavior on its own; nothing is confined until
`sandbox.enabled` is set.

## Navigation

- [Getting Started](getting_started.md) — installation, enabling, a minimal example, checking what's installed
- [Configuration](configuration.md) — the `sandbox:` ceiling, `SKILL.md` capability declarations, and how the two intersect
- [How It Works](how_it_works.md) — the `ScriptTool.executor` extension point, `Sandbox.for` strategy selection, the generated Seatbelt profile, timeout enforcement, extension registration
- [Troubleshooting](troubleshooting.md) — the interpreter-under-`$HOME` problem, non-macOS behavior, diagnosing a denied path

## At a Glance

| | |
|---|---|
| **Confines** | `RobotLab::ScriptTool` executions — i.e. AgentSkill `scripts/` shelled out as tools |
| **Strategies** | `Sandbox::Seatbelt` (macOS, `sandbox-exec`), `Sandbox::Null` (passthrough) |
| **Opt-in via** | `config.sandbox.enabled` (default `false`) — requiring this gem does not turn it on |
| **Grant model** | effective grant = skill's declared `Capabilities` ∩ config `sandbox:` ceiling |
| **Always unconfined** | `trust: core` skills, regardless of platform or config |
| **Extension point** | `RobotLab::ScriptTool.executor = RobotLab::Sandbox::Executor` |
| **Timeout enforcement** | only when this gem is loaded and sandboxing is enabled |

## Links

- [RobotLab Core](https://github.com/MadBomber/robot_lab)
- [RubyGems](https://rubygems.org/gems/robot_lab-sandbox)
- [GitHub](https://github.com/MadBomber/robot_lab-sandbox)
