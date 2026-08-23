# Execution Modes

## Mode selection

Resolve the mode in this order:
1. Explicit user choice in the current request.
2. Existing `loop/EXECUTION.md` when the project was already initialized.
3. Strong wording: `예약`, `ChatGPT`, `Remote`, `AI Folder Remote` => `chatgpt_remote`; `CLI`, `Codex`, `Claude`, `Gemini`, `agy` => `local_cli`.
4. `auto`: when running inside ChatGPT with AI Folder Remote available, prefer `chatgpt_remote`; otherwise use a verified local CLI.

Never run both backends concurrently for one project. Switching modes requires the current loop to be IDLE and the old scheduler/process to be disabled first.

## Local CLI discovery

Probe only non-mutating help/version commands. Never assume syntax from memory when help is available.
Suggested preference when user gave none: existing project configuration first, then Codex, Claude, Gemini, agy. This order is a default, not a quality claim.

Current supported command shapes must be verified from each installed CLI help before writing `AGENT_CMD`:
- Codex: non-interactive `codex exec`; workspace-write/full-auto only when the repository safety policy allows edits.
- Claude: non-interactive `claude -p`; use an edit-allowing permission mode, never bypassPermissions by default.
- Gemini: non-interactive `gemini -p`; use `approval-mode auto_edit`, never yolo by default.
- agy: non-interactive `agy --print`; use `--mode accept-edits`, never dangerously-skip-permissions by default.

The generated prompt should tell the CLI to read `loop/PROMPT.md` completely and execute exactly one iteration. The orchestrator launches a fresh CLI session per attempt.
