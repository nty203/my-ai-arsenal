# Autonomous Development Execution

- execution_mode: local_cli
- preferred_cli: auto
- selected_cli: none
- agent_command: none
- auto_continue: true
- autonomous_improvement_enabled: true
- improvement_after_planned_work_only: true
- improvement_candidate_limit: 5
- improvement_requires_evidence: true
- improvement_requires_verifiable_outcome: true
- stop_when_no_valuable_work: true
- project_completion_check: true
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

## Remote continuous loop

- remote_continuous_enabled: false
- remote_orchestrator_pid: none
- remote_max_loops: 0
- remote_poll_seconds: 2
- remote_startup_timeout_seconds: 180
- remote_run_timeout_seconds: 3600

## Local loop

- local_loop_enabled: false
- local_loop_pid: none
- local_max_loops: 0

Mode values: `auto`, `chatgpt_remote`, `local_cli`.
Task priority: READY user work > verified blocker/regression > explicit planned work > DESIGN gap > autonomous improvement. Autonomous improvement runs only after planned work is exhausted, must have evidence and a verifiable outcome, and never overwrites INBOX. `PROJECT_COMPLETE` stops further automatic iterations until new user work or explicit resume.
Only one scheduler, remote continuous orchestrator, or local CLI loop may actively drive a project at a time.
