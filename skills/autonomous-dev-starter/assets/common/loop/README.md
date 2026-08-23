# Autonomous Development Control

`autonomous-dev-starter` owns installation and mode selection.

Core files:
- `EXECUTION.md`: backend and safety policy
- `PROJECTS.md`: allowed targets and existing Quality Gates
- `RUN_STATE.md`: lock/failure/circuit state shared across execution modes
- `PROMPT.md`: one-iteration agent contract supplied by the selected mode

Execution modes:
- `chatgpt_remote`: each ChatGPT Automation occurrence runs one iteration through AI Folder Remote.
- `local_cli`: `loop.ps1` repeatedly launches fresh headless CLI sessions.

Only one backend may be active for a project at a time.
