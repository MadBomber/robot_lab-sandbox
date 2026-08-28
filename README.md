# RobotLab::Sandbox

OS-level confinement for [RobotLab](https://github.com/MadBomber/robot_lab) skill scripts.

`robot_lab` core has no notion of sandboxing at all — every AgentSkill script
runs unconfined. Requiring `robot_lab-sandbox` installs a `RobotLab::ScriptTool`
executor that, when turned on in config, confines each script to a declared,
ceiling-clamped set of capabilities: which paths it may read and write,
whether it may reach the network, and how long it may run.

## Installation

```ruby
gem "robot_lab"
gem "robot_lab-sandbox"
```

## Usage

Requiring the gem is enough to wire it in; confinement itself stays opt-in via
config, same as it always has:

```ruby
require "robot_lab"
require "robot_lab/sandbox"
```

```yaml
# config/robot_lab.yml
sandbox:
  enabled: true          # opt-in; off = scripts run exactly as robot_lab core alone runs them
  fs_read: ["."]         # ceiling: paths any skill may read (relative to cwd)
  fs_write: []            # ceiling: paths any skill may write
  network: false           # ceiling: may any skill use the network
  timeout: 60               # ceiling: max seconds a skill script may run
```

A skill's own `SKILL.md` front matter declares what it *wants*
(`fs_read`/`fs_write`/`network`/`timeout`/`trust`); the effective grant is the
intersection of that declaration and the config ceiling above. See
`RobotLab::Capabilities` in `robot_lab` core.

## How it works

- **macOS** — each script is wrapped in a generated deny-by-default
  `sandbox-exec` (Seatbelt) profile derived from the effective grant. `$HOME`
  is never implicitly readable, so SSH keys and cloud credentials stay out of
  reach unless a path under `$HOME` is explicitly granted.
- **Other platforms** — a passthrough (`RobotLab::Sandbox::Null`), with a
  one-time warning that confinement is macOS-only.
- **`trust: core` skills** — always a passthrough, regardless of platform.

OS-level confinement is therefore best-effort and platform-specific; it is
never a hard dependency of `robot_lab` core.

## Development

```bash
bundle exec rake test        # Run full test suite
bundle exec rake quality     # Tests + coverage + RuboCop + Flog + Flay
bin/console                  # IRB session with the gem loaded
```

## License

MIT
