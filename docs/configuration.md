# Configuration

Two things combine to decide what a skill script may actually do: what the
skill **declares** it wants, and a global **ceiling** on what any skill may
ever have. `RobotLab::Capabilities` (defined in `robot_lab` core, since
`AgentSkill` needs it regardless of whether this gem is loaded) represents
both sides and computes the intersection.

## The `sandbox:` Ceiling

Declared in `robot_lab` core's `config/defaults.yml`, read by
`Capabilities.ceiling` and `Sandbox.enabled?`:

```yaml
sandbox:
  enabled: false        # opt-in; off = scripts run exactly as robot_lab core alone runs them
  fs_read: ["."]        # ceiling: paths any skill may read (relative to cwd)
  fs_write: []           # ceiling: paths any skill may write
  network: false          # ceiling: may any skill use the network
  timeout: 60               # ceiling: max seconds a skill script may run
```

| Key | Default | Description |
|-----|---------|-------------|
| `sandbox.enabled` | `false` | Turn on OS-level confinement for skill scripts. Read by `RobotLab::Sandbox.enabled?`. |
| `sandbox.fs_read` | `["."]` | Ceiling: paths any skill script may read (relative to cwd) |
| `sandbox.fs_write` | `[]` | Ceiling: paths any skill script may write |
| `sandbox.network` | `false` | Ceiling: whether any skill script may use the network |
| `sandbox.timeout` | `60` | Ceiling: max seconds a skill script may run |

Set these the same way as any other RobotLab config — a project's
`./config/robot_lab.yml`, the user's `~/.config/robot_lab/config.yml`, or
environment variables:

```sh
export ROBOT_LAB_SANDBOX__ENABLED=true
export ROBOT_LAB_SANDBOX__NETWORK=true
```

This section exists in `robot_lab` core whether or not `robot_lab-sandbox` is
loaded — core just doesn't act on it. Without this gem, scripts always run
unconfined no matter what these values say.

## Per-Skill Declaration (`SKILL.md` Front Matter)

Each skill declares what it **wants** directly in its `SKILL.md` front matter,
alongside `name`/`description`:

```markdown title="skills/deploy-checker/SKILL.md"
---
name: deploy-checker
description: Verifies a deployment's health before promoting it.
fs_read: ["./data", "/etc/hosts"]
fs_write: ["./out"]
network: true
timeout: 30
trust: external   # or "core" for trusted, always-unconfined skills
---
```

`AgentSkill` parses this into a `Capabilities` object via
`Capabilities.from_front_matter` — every value is normalized and defaulted,
so a malformed or partial declaration degrades to the safe default rather
than raising.

| Key | Type | Default | Coercion |
|-----|------|---------|----------|
| `fs_read` | `Array<String>` | `[]` | `Array(...)` then `to_s` on each entry |
| `fs_write` | `Array<String>` | `[]` | Same |
| `network` | `Boolean` | `false` | Any truthy value becomes `true` |
| `timeout` | `Integer` | `60` | `to_i`; anything not positive becomes the default |
| `trust` | `String` | `"external"` | Must be `"core"` or `"external"`, else falls back to `"external"` |

## The Intersection

The script actually runs under the **intersection** of the skill's declared
`Capabilities` and the `sandbox:` ceiling — computed by `Capabilities#intersect`:

| Field | Rule |
|-------|------|
| `fs_read` / `fs_write` | A requested path survives only when it **is** a ceiling root or lives beneath one. Both sides are `File.expand_path`ed first, so `~` and relative paths resolve before comparison. |
| `network` | `declared && ceiling` — both sides must allow it. |
| `timeout` | The **smaller** of the two. |
| `trust` | The **declared** value, unchanged — the ceiling never carries a `trust`. |

So a ceiling of `fs_read: ["."]` grants nothing outside the working directory
even if a skill's front matter asks for `/etc`. And a skill that doesn't
declare `network: true` gets no network access no matter how permissive the
ceiling is.

```ruby
declared = RobotLab::Capabilities.from_front_matter(skill_front_matter)
grant    = declared.intersect(RobotLab::Capabilities.ceiling)
```

## `trust: core` — Bypassing Confinement

A skill declaring `trust: core` is exempt from OS-level confinement
entirely — `Sandbox.for` always returns `Sandbox::Null` for it, on every
platform, regardless of the `sandbox:` ceiling or `sandbox.enabled`. Reserve
this for skill bundles you wrote and audited yourself; it is not something a
skill should be able to grant itself casually, since it opts the script out
of every protection this gem provides.

## What Changes When This Gem Isn't Loaded

Nothing about `Capabilities` or the `sandbox:` config schema depends on
`robot_lab-sandbox` — they live in core. What's missing without this gem is
**enforcement**: `RobotLab::ScriptTool.executor` stays `nil`, so
`ScriptTool.execute` always takes the plain `Open3.capture2e` path — no
confinement, no timeout — regardless of what `Capabilities` or `sandbox:`
say. See [How It Works](how_it_works.md) for the mechanics.
