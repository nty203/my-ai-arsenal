# ChatGPT Automation Handoff

Use this only after bootstrap/preflight and two fresh-session pilot iterations PASS with both logs reviewed for duplicate runs, unfinished claims, retry storms, and clean terminal/UI-idle handoff.

## Creation conditions

- execution_mode is `chatgpt_remote`
- AI Folder Remote was verified against the target project
- RUN_STATE is IDLE and circuit is closed
- user supplied a schedule/cadence, or explicitly asked to create a scheduled loop
- the project has at least one verified Quality Gate

Do not invent a schedule when none was supplied.

## Automation prompt contract

The scheduled prompt must include the absolute project root and instruct ChatGPT to:
1. use AI Folder Remote, not local coding CLIs
2. read `loop/EXECUTION.md` and `loop/PROMPT.md` first
3. honor STOP/circuit/duplicate-run conditions
4. prefer READY user work, then verified recovery/planned/DESIGN work; only after those are exhausted may it run evidence-backed autonomous improvement
5. complete exactly one target and one vertical slice; never invent low-value work to keep recurrence alive
6. run registered Quality Gates
7. update RUN_STATE and STATUS with evidence, task source, and autonomous evaluation rationale when used
8. stop new iterations when `PROJECT_COMPLETE` is reached
9. never push or deploy without explicit approval

A schedule run is one loop iteration, not an endless process. Recurrence is owned by ChatGPT Automation.

## Remote continuous alternative

When AI Folder Remote exposes continuous Remote capability, use
`assets/remote/browser-driver/` as the portable driver source. Install it as
`loop/browser-driver/` in the target project. It launches real Chrome with one
persistent automation profile, closes restored extra tabs, and keeps one
Playwright context and one reusable tab for the entire loop. Each iteration
navigates that tab to a fresh ChatGPT `/` page, so a prompt is never appended to
the preceding conversation.

Use DOM locators and events rather than desktop coordinates or foreground
focus. Select and verify Chat rather than Work, open the composer `+` menu,
scroll the menu DOM when necessary, choose the exact `AI Folder Remote` row,
and verify a structural plugin token such as its `/plugins/` link before adding
the prompt. Plain `@AI Folder Remote` text is not success. Verify that submit
clears the composer, handle a late Continue-in-Chat routing dialog, and treat
only the actual stop-generation control as busy.

The RUN_STATE start handshake must include an actual RUNNING or RECOVERING
state. A stale active run may be resumed only when the same active task and
run_id and existing claim remain; the recovery agent must refresh `heartbeat_at` immediately after verifying that exact claim; never create a
replacement claim. If a submitted response is still busy at startup timeout,
keep observing that same response instead of opening a duplicate chat; a watch timeout alone never authorizes Stop or a fresh-chat retry. After terminal RUN_STATE,
wait for UI idle before the next fresh chat. Treat `loop/STOP` as graceful: finish an already submitted/adopted iteration, then prevent the next chat. Circuit-open/PAUSED remain hard-stop conditions. Also stop on
SKIP/BLOCKED/FAIL or unsafe profile reuse.

While observing a RUNNING/RECOVERING task, re-evaluate its heartbeat in bounded
intervals. Recover only when the heartbeat is stale *and* the saved response is
idle; resume the same claim in a fresh chat, never create another claim.
Treat `FAIL`, `BLOCKED`, and `SKIP` as terminal before considering state, so a
RECOVERING handoff cannot lead to another automatic fresh chat.

An iteration can occasionally finish before the polling loop observes its
RUNNING transition. In that case, a new terminal `last_result` together with a
non-running state is a conclusive terminal handshake for the submitted
iteration. Accept it and continue closeout; never open retry chats merely
because the transient start state was missed.

Treat a persistent visible connection-lost notice as a special startup fault.
Only when RUN_STATE and the complete claim-directory signature are still
unchanged after the grace period may the driver stop the response through the
DOM stop button, wait for UI idle, and retry in a fresh chat. If either state or
claims changed, never abort or retry automatically. While waiting for the
startup response, poll RUN_STATE concurrently so a late RUNNING handshake is
reported immediately instead of leaving the phase stuck at WAIT_START_RESPONSE.

Use a project-owned profile by default or an explicitly selected, separately
authenticated automation profile. Never read, copy, or print profile contents
or credentials, never delete profile lock files blindly, and fail safely when
another program owns the profile. Keep `assets/remote/driver/` as the unchanged
Windows-app fallback and never run browser, app, scheduled, or local CLI loops
together.
