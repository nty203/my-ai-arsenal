# ChatGPT-native Autonomous Development Contract

## Execution model

You are ChatGPT running one development iteration through `AI Folder Remote`.
Read `loop/EXECUTION.md` first. Do not invoke local Codex, Claude, Gemini, Antigravity, agy, or another AI agent in `chatgpt_remote` mode.
Complete exactly one target and one verifiable vertical slice.

## Entry conditions

1. Confirm PC connection with a harmless read.
2. Read `loop/EXECUTION.md`, `loop/RUN_STATE.md`, and `docs/feedback/INBOX.md`.
3. If `circuit_open: true`, modify nothing and return BLOCKED.
4. Treat a recent RUNNING state as a duplicate run and return SKIP.
5. Select work in this order: first READY user task; otherwise, when `auto_continue: true`, STATUS next objective; otherwise the smallest verifiable DESIGN-to-code gap.
6. If no task can be selected safely, return SKIP without source changes.
7. Record run id, selected/generated task, target app, and start state before implementation.

Generated tasks must not overwrite the user-owned INBOX.

## Required reading

1. Applicable `AGENTS.md` or equivalent project rules.
2. `docs/DESIGN.md` and `docs/STATUS.md`.
3. `loop/PROJECTS.md` for target path and Quality Gates.
4. Relevant Wiki index/pages if present.
5. Target app README, manifest, entry points, source, and tests.
6. Git status and existing contents of files to be changed.

## Scope and safety

- Preserve unrelated user changes.
- Never read or print secrets, credentials, tokens, PEM files, or browser profiles.
- Do not push, deploy, publish, pay, or send external messages without explicit approval.
- Modify the selected target and directly required shared files only.
- Do not invent new test frameworks or validation commands solely for the loop.

## Implementation and Quality Gates

1. Define at most five observable acceptance conditions for a generated task.
2. Reproduce current behavior when practical.
3. Make the smallest change that completes one vertical slice.
4. Run only the target's registered and actually existing gates.
5. Run `git diff --check` when Git is available.
6. Check relevant normal, boundary, and failure paths.
7. For UI changes, inspect the rendered screen or build output when possible.

## Self-healing

On the first gate failure, identify the first root cause and make at most the configured number of directly related repairs.
Then rerun the failed gate and all related gates.
If verification fails again, stop guessing, preserve any READY user task, record evidence, and increment consecutive failures.
Open the circuit at the configured failure threshold.

## Success handoff

Only after every gate passes:
- mark the current INBOX task DONE only when the selected work came from INBOX
- return RUN_STATE to IDLE and clear consecutive failures
- update STATUS with goal, task source, changed files, commands/results, risks, and one next task
- update Wiki only for reusable knowledge
- commit only when both project policy and `commit_allowed` permit it

## Final response

Start with `PASS`, `SKIP`, `BLOCKED`, or `FAIL`.
Report the goal, task source, changed files, verification evidence, state transition, and next action.
Never report PASS from inference alone.
