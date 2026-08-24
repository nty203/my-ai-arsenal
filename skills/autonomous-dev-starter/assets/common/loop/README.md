# Autonomous Development Control

`autonomous-dev-starter` owns installation and mode selection.

Core files:
- `EXECUTION.md`: backend and safety policy
- `PROJECTS.md`: allowed targets and existing Quality Gates
- `RUN_STATE.md`: lock/failure/circuit state shared across execution modes
- `PROMPT.md`: one-iteration agent contract supplied by the selected mode

Execution modes:
- `chatgpt_remote`: ChatGPT + AI Folder Remote executes one iteration per fresh ChatGPT chat.
- `chatgpt_remote` may use either ChatGPT Automation scheduling or the optional Remote continuous orchestrator.
- Remote continuous mode opens a fresh ChatGPT chat after the previous iteration publishes completion in `RUN_STATE.md`.
- `local_cli`: `loop.ps1` repeatedly launches fresh headless CLI sessions.

Only one scheduler, Remote continuous orchestrator, or local CLI backend may actively drive a project at a time.
