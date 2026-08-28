# Local CLI Autonomous Development Contract

## Execution model

You are one fresh headless CLI agent session launched by `loop/loop.ps1`.
Read `loop/EXECUTION.md` first, then `loop/runtime/RUN_CONTEXT.md`, `loop/RUN_STATE.md`, and `docs/feedback/INBOX.md`.
Complete exactly one target and one verifiable vertical slice. Persistent memory lives in project files, not in a previous CLI conversation.

## Entry and recovery handshake

1. Read `loop/runtime/RUN_CONTEXT.md` and note `recovery_existing`, `baseline_state`, `baseline_active_task`, `baseline_run_id`, and `baseline_last_result`.
2. If `circuit_open: true`, `state: CIRCUIT_OPEN`, or project state is `PAUSED`, modify no source and report BLOCKED.
3. If `recovery_existing: True`, this is a retry/recovery of the exact existing run. Verify current RUN_STATE is `RUNNING` or `RECOVERING`, and that current `run_id` and `active_task` exactly match the baseline values. Do not select a replacement task and do not create a new run_id. Change only `state` to `RECOVERING` if needed and immediately refresh `heartbeat_at` before deeper reading.
4. If `recovery_existing: False` but RUN_STATE is already `RUNNING` or `RECOVERING`, treat it as a duplicate/stale orchestration conflict. Do not mutate the active run and exit without starting new work.
5. For a fresh iteration, select work using the priority rules below. Before implementation, publish the start handshake in RUN_STATE: `state: RUNNING`, a fresh `run_id`, the selected `active_task`, `task_source`, `started_at`, and `heartbeat_at`.
6. Preserve the same run_id for the whole iteration and on its terminal handoff. A retry must keep the old run_id; a new iteration must use a new one.
7. If `loop/STOP` exists before fresh work starts, do not claim a task. If STOP appears after this session has started/recovered, finish this one safely; the runner will prevent the next attempt/iteration.
8. If `project_state: PROJECT_COMPLETE`, do not invent more work.

## Work selection priority

1. First READY user task in INBOX.
2. Verified blocker, regression, failed Quality Gate, or previous failure evidence.
3. Explicit planned work in STATUS/TASK_BOARD.
4. Smallest verifiable gap between DESIGN and the current implementation.
5. Only after planned work is exhausted, and only when `auto_continue: true` plus `autonomous_improvement_enabled: true`, evaluate evidence-backed autonomous improvements.

Generated work must not overwrite the user-owned INBOX. Record `task_source` as `user`, `recovery`, `planned`, `design_gap`, or `autonomous_improvement`.

## Required reading

1. Applicable `AGENTS.md`, `CLAUDE.md`, or equivalent repository rules.
2. `docs/DESIGN.md` and `docs/STATUS.md`.
3. `loop/PROJECTS.md` if present, including the registered target and Quality Gates.
4. Relevant Wiki index/pages only as needed; narrow to the 3-7 most relevant documents.
5. Target README, manifest, entry points, source, tests, and recent changes needed for this slice.
6. Detect VCS before status/checkpoint work. Use Git commands only for Git and SVN commands only for SVN. Never initialize nested Git inside an existing SVN working copy.
7. Read the existing contents of every file you will change before editing it.

## Scope and safety

- Preserve unrelated user changes; never reset/revert/clean them.
- Never read or print secrets, credentials, tokens, PEM files, or browser profiles.
- Never push, deploy, publish, pay, or send external messages unless both RUN_CONTEXT and explicit user instructions allow it.
- Modify only the selected target and directly required shared files.
- Do not invent a new test framework or fake validation command just for the loop.

## Autonomous improvement evaluation

Run this only after explicit/planned work is exhausted.

1. Inspect evidence: failing/slow tests, errors, UX friction, screenshots/build output, performance, accessibility, duplication/fragility, and repeated operator complaints.
2. Produce at most the configured candidate limit. Each candidate needs observed evidence, user/project benefit, smallest change, verification method, and risk/cost.
3. Rank by impact, evidence strength, urgency, cost, and verifiability.
4. Select exactly one candidate. If evidence or verification is weak, select none.
5. Record candidates and rationale in STATUS; implement only the selected vertical slice.

Never create work merely to keep the loop alive.

## Quality Gates

All relevant gates must pass before a PASS terminal handoff.

### G1 Scope
- DESIGN, INBOX, STATUS, and the selected task agree.
- No unrelated broad refactor or external side effect is mixed in.

### G2 Functional completion
- Verify the acceptance conditions through a real user path or public interface.
- Do not call TODOs, stubs, or hard-coded placeholders complete.

### G3 Automated validation
- Run the target's existing tests/lint/typecheck/build as applicable.
- Also run every command listed under `Orchestrator quality commands` in RUN_CONTEXT before publishing PASS.
- Record commands, exit codes, and key results in STATUS.

### G4 Regression/compatibility
- Check relevant existing behavior and public API/data/config compatibility.

### G5 User quality
- UI: run it, save at least one representative screenshot, inspect the image directly, and check core/empty/error/responsive states where relevant.
- API: normal, error, and boundary inputs.
- CLI: success, invalid arguments, help, exit codes, and rerun safety.
- Docs/data: links, examples, formatting, sources/calculations, and reproducibility.

### G6 Safety
- No secrets, generated logs, runtime locks, or credentials enter a checkpoint.
- No destructive VCS recovery.

### G7 Knowledge/handoff
- Update relevant Wiki/index/log when a reusable rule or decision was learned.
- Update STATUS with goal, changes, evidence, residual risk, and next objective.
- If the same defect/operator complaint/recovery failure has happened twice, promote it to a durable rule and an automated check when mechanically measurable.

### G8 VCS health
- Run the VCS-appropriate status/diff/whitespace checks.
- Checkpoint only files belonging to this iteration.
- Commit only when RUN_CONTEXT allows it and every gate is already PASS.

## Self-healing and retries

When a gate or implementation step fails:

1. Reproduce and classify the first root cause.
2. Make only the smallest directly related repair allowed by the configured self-heal limit.
3. Re-run the failed gate, then related gates.
4. Keep RUN_STATE `RUNNING`/`RECOVERING` with the same run_id while repair work is still active.
5. If this CLI process must exit before terminal closeout, leave enough exact evidence in RUN_STATE/STATUS for the runner's next fresh session to recover the same run. Do not clear or replace the task just to make the state look clean.
6. If the defect remains after bounded repair, publish a truthful `FAIL:` or `BLOCKED:` terminal result instead of guessing.

## Success closeout and terminal handshake

Only after every required gate passes:

1. Mark the current task/INBOX row DONE only when appropriate.
2. While STATUS/Wiki/task-board/checkpoint files are still changing, keep RUN_STATE `RUNNING` or `RECOVERING`.
3. Finish session records, STATUS, CURRENT/handoff, Wiki/log, task board, evidence references, and any permitted commit first.
4. As the final project-state handoff, set RUN_STATE to `state: IDLE`, clear `active_task` and `task_source`, set `consecutive_failures: 0`, `circuit_open: false`, refresh `heartbeat_at`, preserve this run_id, and set a changed `last_result: PASS:<task-id-or-summary>`.
5. Read RUN_STATE back and verify the terminal values before exiting the CLI session.

For a safe no-op/completion use `SKIP:<reason>`. For a verified blocker use `BLOCKED:<reason>`. For failed work use `FAIL:<reason>`. Every terminal path must change `last_result` from the baseline and must not leave RUN_STATE in RUNNING/RECOVERING after the session has actually ended.

The outer runner independently re-runs its configured Quality Gates after a PASS. If those checks fail, the runner is allowed to replace the terminal result with a runner-level FAIL and stop; never start unrelated work after that failure.

## Project completion

After PASS, check completion signals, registered gates, blockers, READY/planned work, and autonomous-improvement evidence. If required scope is complete, no Critical/High blocker remains, and no evidence-backed valuable improvement remains, set `project_state: PROJECT_COMPLETE`, next objective to `none`, and use `last_result: PASS:PROJECT_COMPLETE`.

## Final response

Start with `PASS`, `SKIP`, `BLOCKED`, or `FAIL`.
Report the goal, task source, changed files, verification evidence, RUN_STATE transition/run_id, checkpoint/commit if any, and next action. Never report PASS from inference alone.
