# Autonomous Development State

- state: IDLE
- active_task: none
- task_source: none
- target: none
- run_id: none
- started_at: none
- heartbeat_at: none
- consecutive_failures: 0
- circuit_open: false
- last_result: NOT_RUN
- last_error: none
- last_evidence: none

State values: `IDLE`, `RUNNING`, `RECOVERING`, `PAUSED`, `CIRCUIT_OPEN`.
A duplicate active run must not be started. Stale-lock recovery rules are project-specific and must be recorded before mutation.
