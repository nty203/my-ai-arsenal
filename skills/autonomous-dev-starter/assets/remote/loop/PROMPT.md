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
5. Select work in this order: READY user task > verified blocker/regression > explicit planned task > smallest verifiable DESIGN gap.
6. Only when planned work is exhausted and both `auto_continue: true` and `autonomous_improvement_enabled: true`, run autonomous improvement evaluation. Generate at most the configured candidate limit and select one evidence-backed, verifiable improvement.
7. If `project_state: PROJECT_COMPLETE`, or no valuable task can be selected safely, do not invent work; return SKIP/COMPLETE without source changes.
7. Before implementation, write `state: RUNNING`, a fresh `run_id`, `active_task`, `started_at`, and `heartbeat_at` to RUN_STATE. This is the Remote continuous start handshake.

Generated tasks must not overwrite the user-owned INBOX. Record `task_source` as `user`, `recovery`, `planned`, `design_gap`, or `autonomous_improvement`.

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

## Autonomous improvement evaluation

Run this only after all explicit planned work is exhausted.

1. Inspect current evidence: failing/slow tests, logs, UX flow, screenshots/build output, performance data, accessibility, duplication/fragility, and recent repeated failure patterns.
2. Produce at most 5 candidates. Each candidate must state: observed evidence, user/project benefit, smallest change, verification method, risk/cost.
3. Rank by impact, evidence strength, urgency, cost, and verifiability. Prefer fixes that improve observable product quality over cosmetic churn or speculative refactors.
4. Select exactly one candidate. If evidence or verification is weak, select none.
5. Record the candidate list and rationale in STATUS, then implement only the selected vertical slice.

Never create work merely to keep the loop alive.

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
- mark the current INBOX/task row DONE only when appropriate
- while closeout files are still being changed, keep RUN_STATE `state: RUNNING`; do not publish terminal IDLE early
- update the session record, STATUS, CURRENT/handoff, Wiki/log, task board, evidence references, and any permitted commit first
- mark the active claim `handoff_ready: true`, verify it, then release/remove the claim
- **as the final mutating operation of the iteration**, return RUN_STATE to IDLE, clear `active_task`, clear consecutive failures, refresh heartbeat, set the exact next task, and change `last_result` to `PASS:<task-id-or-summary>`
- read back terminal RUN_STATE/handoff for verification; after terminal RUN_STATE is published, do not perform any further mutating tool/file operations
- only then produce the final ChatGPT response

## Project completion check

After a PASS, check DESIGN completion signals, required gates, blockers, READY/planned work, and the autonomous improvement evaluation. If completion signals pass, no Critical/High blocker remains, and no evidence-backed valuable improvement remains, set `project_state: PROJECT_COMPLETE`, next objective to `none`, and publish `last_result: PASS:PROJECT_COMPLETE`. A new READY user task or explicit resume may reactivate the project.

## Terminal-state handshake

Every exit path must publish a changed `last_result` before replying. Use `PASS:...`, `SKIP:...`, `BLOCKED:...`, or `FAIL:...`. PASS/SKIP normally end in IDLE; circuit-open ends in CIRCUIT_OPEN; a deliberate human pause may use PAUSED. Never leave RUN_STATE as RUNNING after the iteration has actually ended.

## Final response

Start with `PASS`, `SKIP`, `BLOCKED`, or `FAIL`.
Report the goal, task source, changed files, verification evidence, state transition, and next action.
Never report PASS from inference alone.
