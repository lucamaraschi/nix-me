# Repository tools

Operational scripts are grouped by lifecycle:

- `development`: local VM and workstation helpers;
- `installation`: installation and project synchronization support;
- `local-ai`: explicit DS4/Pi setup and hardware/runtime diagnostics;
- `release`: macOS signing, packaging, notarization, and feed generation.

Tools may orchestrate applications and packages but must not become a second
implementation of their business logic.
