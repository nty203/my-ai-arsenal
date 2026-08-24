# Autonomous Development Project Rules

Read `loop/EXECUTION.md` before any autonomous iteration.

- Complete one target and one verifiable vertical slice per iteration.
- Preserve unrelated user changes; never use destructive Git recovery.
- Never read or print secrets, credentials, PEM files, tokens, or browser profiles.
- Run only Quality Gates that actually exist in this project.
- Keep push, deploy, publish, payment, and external messaging behind explicit approval.
- Record verified results and the next task in `docs/STATUS.md`.
- User READY work in `docs/feedback/INBOX.md` has absolute priority.
- Planned work and verified failures come before autonomous improvement.
- Autonomous improvement is allowed only after planned work is exhausted and only when evidence plus a verifiable outcome exist.
- Generated work must never overwrite INBOX; record its source and rationale in STATUS/RUN_STATE.
- When project completion signals pass and no valuable candidate remains, mark `PROJECT_COMPLETE` instead of inventing work.
- `chatgpt_remote` must not invoke local coding CLIs.
- `local_cli` must use only the selected CLI and the bounded loop runner.
