---
name: autonomous-dev-loop
description: Set up, upgrade, diagnose, or harden a file-handoff autonomous development loop that launches a fresh headless coding-agent session each iteration. Use for repeated self-healing development across frontend, backend, full-stack, game, CLI, automation, documentation, or data projects, including Quality Gates, bounded retries, circuit breakers, STATUS handoff, Git checkpoints, and LLM Wiki retrieval.
---

# Autonomous Development Loop

Build a generic loop whose project-specific behavior comes from configuration, not from branching the orchestrator for every framework.

## Workflow

1. Read the target repository's applicable AGENTS.md or equivalent instructions.
2. Detect the existing VCS first. Preserve an existing Git or SVN source-of-truth and never initialize nested Git inside an SVN working copy. If both Git and SVN succeed because the project is nested, auto mode prefers Git only when that Git repo has a configured remote; otherwise it preserves SVN. Use `VCS_PREFERENCE` only when project evidence requires an explicit override.
3. Inspect VCS status and preserve unrelated user changes.
4. Inspect existing loop, design, status, feedback, logs, tests, and Wiki structure.
5. If the loop exists, merge surgically; do not overwrite project decisions.
6. If it does not exist, copy the files under `assets/template/` into the target root.
7. Read `references/project-profiles.md` and select the narrowest matching profile.
8. Set AGENT_CMD, QUALITY_COMMANDS, timeouts, retry limits, VCS mode, and safety policy in env.ps1.
9. Fill DESIGN with stable purpose and constraints; fill STATUS with current evidence and one next task.
10. Keep INBOX for user-owned priority instructions.
11. Run `powershell -File loop/loop.ps1 -PreflightOnly`.
12. Parse PowerShell files and run the VCS-appropriate status/whitespace checks.
13. Pilot with exactly two fresh-session iterations before allowing an unbounded run; inspect both logs and tune timeout/turn values from observed duration rather than guesswork.
14. Record learned architecture or failure rules in the project's Wiki, index, and audit log.
15. Commit only the files changed for this loop setup when the detected VCS and policy allow it.

## Required invariants

- Complete one verifiable vertical slice per iteration.
- Treat test, build, or observed behavior as completion evidence.
- Launch every iteration and retry as a fresh headless session; persistent memory lives in files, not the prior conversation/session.
- Bound retries and stop after repeated failures with a circuit breaker.
- Treat STOP as graceful: if it appears during an active agent session, let that session finish and prevent the next retry/iteration instead of killing the current work.
- Hold an exclusive lock to prevent duplicate loops.
- Never use destructive VCS recovery on user changes.
- If the same defect/operator complaint/recovery failure occurs twice, promote it into a durable rule and into an automated check when mechanically measurable.
- UI work requires rendered visual evidence inspection in addition to code/test success.
- Keep push, deploy, payment, credentials, and external publishing behind explicit approval.
- Keep volatile runtime state and logs out of Git.
- Explore Wiki knowledge from index to keyword search to a 3-7 document shortlist.

## Merge rules

Preserve existing DESIGN content unless it is an untouched placeholder.
Preserve STATUS history and append a migration section when upgrading.
Preserve INBOX exactly unless the user asks to consume or edit it.
Keep existing project test commands; do not invent a new framework only for the loop.
If an existing runner has platform-specific behavior, retain it and port the reliability features around it.

## Validation

Require all of the following before reporting completion:

- PowerShell parser accepts loop.ps1 and env.ps1.
- PreflightOnly exits 0 for the detected Git or SVN working copy.
- Runtime, logs, lock, and STOP paths are excluded from version control according to that VCS.
- A simulated failing command produces a non-zero result without deleting user changes.
- Configuration documents at least one relevant Quality Gate command.
- Two fresh-session pilot iterations have readable logs and no retry storm, duplicate runner, or unfinished handoff.
- README or equivalent usage surface explains the new reusable loop.
- VCS diff/status contains no unrelated user files in the proposed checkpoint.

Do not start an endless agent run merely to validate installation.


## Unified starter routing

일반 사용자의 자율 개발 진입점은 `autonomous-dev-starter`다.
Starter가 프로젝트를 초기화하고 `chatgpt_remote` 또는 `local_cli`를 선택한다.
`local_cli`가 선택된 경우에만 이 스킬의 runner 패턴과 템플릿을 사용한다.
`chatgpt_remote`에서는 로컬 AI CLI runner를 실행하지 않고 ChatGPT + AI Folder Remote 경로를 사용한다.
Remote continuous orchestration이 필요한 경우에도 이 스킬의 `loop.ps1`을 재사용하지 않는다. `autonomous-dev-starter`의 chatgpt_remote 경로와 AI Folder Remote의 RUN_STATE 기반 새-채팅 orchestrator를 사용한다.
두 실행 백엔드를 한 프로젝트에서 동시에 활성화하지 않는다.
