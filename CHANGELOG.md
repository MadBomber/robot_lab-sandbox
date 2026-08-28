# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Extracted from `robot_lab` core: `RobotLab::Sandbox`, `RobotLab::Sandbox::Seatbelt`,
  `RobotLab::Sandbox::Null`, and the new `RobotLab::Sandbox::Executor`, which installs
  itself as `RobotLab::ScriptTool.executor` when this gem is required. `robot_lab` core
  now runs every skill script unconfined unless `robot_lab-sandbox` is loaded.

[Unreleased]: https://github.com/MadBomber/robot_lab-sandbox/compare/v0.1.0...HEAD
