# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.1] - 2026-11-19

### Changed

- **Minimum Ruby raised to 4.0.9.** `required_ruby_version` is now `>= 4.0.9` (was `>= 3.2.0`), and a `.ruby-version` file pins development to 4.0.9.
- **Requires `robot_lab ~> 0.6`** (was `~> 0.3.0`). Verified against robot_lab 0.6.1 and ruby_llm 2.2.3; no code changes were needed.

## [0.2.8] - 2026-09-09

Initial public release, versioned 0.2.8 to join the core lockstep (the gem was never published at its working version 0.1.0). It resolves the released `robot_lab` core gem v0.2.8 from RubyGems instead of the local sibling checkout (local-path development remains available via `BUNDLE_GEMFILE=Gemfile.local`). Also in this release: gem lifecycle tasks moved from the Rakefile to the asgard task runner.

### Added
- Extracted from `robot_lab` core: `RobotLab::Sandbox`, `RobotLab::Sandbox::Seatbelt`,
  `RobotLab::Sandbox::Null`, and the new `RobotLab::Sandbox::Executor`, which installs
  itself as `RobotLab::ScriptTool.executor` when this gem is required. `robot_lab` core
  now runs every skill script unconfined unless `robot_lab-sandbox` is loaded.

[Unreleased]: https://github.com/MadBomber/robot_lab-sandbox/compare/v0.2.8...HEAD
[0.2.8]: https://github.com/MadBomber/robot_lab-sandbox/releases/tag/v0.2.8
