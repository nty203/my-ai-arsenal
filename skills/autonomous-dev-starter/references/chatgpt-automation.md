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
4. prefer a READY user task; otherwise follow `auto_continue`
5. complete exactly one target and one vertical slice
6. run registered Quality Gates
7. update RUN_STATE and STATUS with evidence
8. never push or deploy without explicit approval

A schedule run is one loop iteration, not an endless process. Recurrence is owned by ChatGPT Automation.

## Remote continuous alternative

When AI Folder Remote exposes `start_chatgpt_remote_loop`, `chatgpt_remote_loop_status`, and `stop_chatgpt_remote_loop`, a user may choose continuous Remote instead of a time schedule. It must launch one fresh ChatGPT chat per iteration, wait for the RUN_STATE start/finish handshake, and stop on STOP, circuit-open, SKIP/BLOCKED/FAIL, or timeout. Do not run this driver together with a scheduled Automation or local CLI loop.
