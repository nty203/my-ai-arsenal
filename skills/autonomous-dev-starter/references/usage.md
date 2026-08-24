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
- `Remote 연속 개발 시작` — when supported, start the AI Folder Remote continuous orchestrator; each task runs in a fresh ChatGPT chat and the next chat starts immediately after RUN_STATE completion.
- `Remote 연속 개발 상태` — read the orchestrator status without starting another iteration.
- `Remote 연속 개발 재개` — after explicit resume intent, clear only `loop/STOP` with `RESUME` confirmation and start the Remote continuous orchestrator again.
- `Remote로 전환` / `CLI로 전환` — safely stop the old backend, preflight the new one, then switch.
- `루프 중지` — stop/disable the active backend without deleting project state.
- `내 의견 반영: <내용>` / `다음 작업에 반영: <내용>` — save the request as the next `READY` user-priority task in `docs/feedback/INBOX.md`.
- `우선 작업: <내용>` — make the request the next explicit user-priority task.
- `<작업> 보류` — change that user task to `PAUSED` so automatic work can continue without consuming it.

## Default behavior

`개발 시작` means `auto_continue: true`. User READY work has priority. When no READY task exists, one smallest verifiable task is selected from STATUS/DESIGN per iteration.

A scheduled Remote Automation run is one iteration. Remote continuous mode may repeat iterations in fresh ChatGPT chats using RUN_STATE as the completion handshake. A local CLI process may repeat iterations under `loop.ps1` until STOP, a configured loop limit, or circuit-open.
