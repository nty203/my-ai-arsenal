# Local CLI Autonomous Development Control

This template uses the same file-handoff state model as the ChatGPT Remote loop, but launches a fresh headless CLI session for each iteration.

Core files:
- `EXECUTION.md`: execution and safety policy
- `PROJECTS.md`: registered targets and real Quality Gates
- `RUN_STATE.md`: active run, recovery, failure, circuit, and project-completion state
- `PROMPT.md`: one-iteration CLI agent contract
- `env.ps1`: verified CLI command and runner settings
- `loop.ps1`: fresh-session orchestrator

The runner refuses to start over an existing `RUNNING`/`RECOVERING` state. After confirming the old CLI process is gone, use `loop.ps1 -RecoverExisting` to resume that exact run/task without creating a replacement claim. Retries inside one runner automatically recover an active RUN_STATE.

`loop/STOP` is graceful: it prevents a new attempt/iteration but does not kill an already running CLI session. `PROJECT_COMPLETE`, `PAUSED`, and `CIRCUIT_OPEN` stop new sessions.
