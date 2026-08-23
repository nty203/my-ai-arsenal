# Autonomous Development Execution

- execution_mode: auto
- preferred_cli: auto
- selected_cli: none
- agent_command: none
- auto_continue: true
- one_vertical_slice_per_run: true
- self_heal_attempts_per_run: 1
- consecutive_failures_before_circuit_open: 2
- commit_allowed: false
- push_allowed: false
- deploy_allowed: false
- credentials_access: forbidden
- bootstrap_state: NEW
- pilot_state: NOT_RUN
- backend_state: INACTIVE

## Remote schedule

- schedule_enabled: false
- schedule_expression: none
- schedule_timezone: project_or_user_local
- automation_id: none

## Local loop

- local_loop_enabled: false
- local_loop_pid: none
- local_max_loops: 0

Mode values: `auto`, `chatgpt_remote`, `local_cli`.
Task priority: READY user work first; with `auto_continue: true`, choose exactly one smallest verifiable task from STATUS, then DESIGN/repository evidence without overwriting INBOX.
