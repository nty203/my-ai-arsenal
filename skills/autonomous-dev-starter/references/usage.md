# Usage

The user should only need the `autonomous-dev-starter` entry skill.

## Minimal commands

- `개발 시작` — auto-detect backend, bootstrap, preflight, pilot.
- `ChatGPT Remote로 개발 시작` — use ChatGPT + AI Folder Remote.
- `매일 오후 12시에 ChatGPT Remote로 개발 시작` — after pilot PASS, create the requested ChatGPT Automation.
- `CLI로 개발 시작` — auto-select a verified local headless CLI.
- `Codex로 개발 시작` — local CLI mode with Codex preferred.
- `Claude로 개발 시작`, `Gemini로 개발 시작`, `agy로 개발 시작` — same pattern.
- `개발 계속` — continue using the stored execution mode.
- `Remote로 전환` / `CLI로 전환` — safely stop the old backend, preflight the new one, then switch.
- `루프 중지` — stop/disable the active backend without deleting project state.

## Default behavior

`개발 시작` means `auto_continue: true`. User READY work has priority. When no READY task exists, one smallest verifiable task is selected from STATUS/DESIGN per iteration.

A Remote Automation run is one iteration. A local CLI process may repeat iterations under `loop.ps1` until STOP, a configured loop limit, or circuit-open.
