# Autonomous Development Project Rules

Read `loop/EXECUTION.md` before any autonomous iteration.

- Complete one target and one verifiable vertical slice per iteration.
- Preserve unrelated user changes; never use destructive Git recovery.
- Never read or print secrets, credentials, PEM files, tokens, or browser profiles.
- Run only Quality Gates that actually exist in this project.
- Keep push, deploy, publish, payment, and external messaging behind explicit approval.
- Record verified results and the next task in `docs/STATUS.md`.
- User READY work in `docs/feedback/INBOX.md` has priority.
- When `auto_continue: true`, generated work may come from STATUS/DESIGN but must not overwrite INBOX.
- `chatgpt_remote` must not invoke local coding CLIs.
- `local_cli` must use only the selected CLI and the bounded loop runner.
