# Changelog

All notable changes to ahu are tracked in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres
to [Semantic Versioning](https://semver.org/) once 1.0.0 ships.

## [Unreleased]

### Added

- Initial repository scaffolding: `README.md`, `CLAUDE.md`, `VERSION`
  (`0.0.1`), `CHANGELOG.md`, and empty `src/` / `tests/` / `examples/`
  trees.
- `docs/design.md` — design specification for ahu, the OTP-style
  framework that runs on top of kaikai's actor and effect primitives.
  Pins the seven load-bearing decisions: behavior surface, supervision
  strategies, process registry, hot code reload, distribution,
  ahu-Tongariki MVP scope, and repository layout.
- `docs/roadmap.md` — milestone series for ahu following the Rapa Nui
  naming convention shared with kaikai (Tongariki, Anga Roa, Orongo,
  Anakena), with scope, definition-of-done, and sequencing constraints.
- `docs/lane-experience-ahu-design.md` — retrospective for the design
  lane.
