# ChatGPT Automation Handoff

Use this only after bootstrap/preflight and one real pilot iteration PASS.

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

When AI Folder Remote exposes `start_chatgpt_remote_loop`, `chatgpt_remote_loop_status`, and `stop_chatgpt_remote_loop`, a user may choose continuous Remote instead of a time schedule. It must launch one fresh ChatGPT chat per iteration, positively verify that the ChatGPT window is foreground, wait for the new-chat WebView composer to stabilize, click the composer, then select the AI Folder Remote mention without keyboard-layout/IME corruption. Choose `Chat으로 계속하기` whenever ChatGPT presents a Work-vs-Chat routing choice, verify that the composer actually submitted, then wait for the RUN_STATE start/finish handshake. If the composer remains populated after retries, or the window cannot be brought foreground, treat launch as failed rather than waiting for a false handshake. Stop on STOP, circuit-open, SKIP/BLOCKED/FAIL, or timeout. Do not run this driver together with a scheduled Automation or local CLI loop.

For installations that include the separate browser driver, prefer semantic
web selectors over window coordinates: locate the ChatGPT composer by role,
commit `AI Folder Remote`, verify its `/plugins/` link token inside the
composer, and only then submit. Use a dedicated browser profile with one-time
manual login; never read or print profile contents or credentials. Keep the
Windows-app driver unchanged as a fallback, and never run both loops together.

If an installation already maintains a non-default, separately authenticated
browser profile for ChatGPT, a normal Selenium driver may reuse that profile
without copying or inspecting it. Do not use a person’s default Chrome profile,
do not remove profile lock files, and fail safely when that profile is in use.
