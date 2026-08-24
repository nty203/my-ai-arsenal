# User Priority Queue

This file is user-owned. A READY task always overrides automatically generated work.
When no READY task exists, the loop may continue only when `loop/EXECUTION.md` has `auto_continue: true`.

## Task 1

- state: EMPTY
- target_app:
- objective:
- acceptance:
  -
- deploy: forbidden

State values:
- `EMPTY`: no explicit user-priority work; auto-continue may still select work.
- `READY`: next loop must process this task first.
- `PAUSED`: retain task but do not run it.
- `DONE`: completed and verified.
- `CANCELED`: explicitly withdrawn by the user; never select it again.

Generated tasks are recorded in RUN_STATE/STATUS, not written into this file.