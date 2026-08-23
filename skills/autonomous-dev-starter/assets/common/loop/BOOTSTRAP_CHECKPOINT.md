# Bootstrap Checkpoint

- phase: NOT_STARTED
- status: PENDING
- last_completed: none
- next_step: read_only_diagnosis
- resume_policy: continue_from_next_step
- last_verified_at: none

## Required behavior

- Read this file first whenever bootstrap is incomplete.
- After every bootstrap phase, persist `last_completed` and `next_step` before starting the next phase.
- If a ChatGPT turn or remote tool call is interrupted, verify completed outputs and resume instead of restarting.
- Prefer small file writes, short shell commands, and immediate verification.
- Avoid non-ASCII path literals inside Windows PowerShell source when UTF-8 BOM cannot be guaranteed.
- If a non-ASCII path is unavoidable, discover it from an ASCII parent path or write the script with BOM explicitly.

This file is bootstrap state only. Normal development progress remains in `docs/STATUS.md` and `loop/RUN_STATE.md`.