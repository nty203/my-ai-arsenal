---
name: autonomous-dev-starter
description: 단 하나의 진입점으로 프로젝트를 자율 개발용으로 진단·초기화한 뒤 ChatGPT Automation + AI Folder Remote 또는 로컬 headless CLI 실행 모드까지 자동 연결하는 시작 스킬. 사용자가 "개발 시작", "루프 개발 시작", "자율 개발 시작"이라고 하면 프로젝트 구조, Git, 보호 파일, Quality Gate, 상태 문서, 실행 모드를 준비하고 파일럿 검증 후 선택된 루프를 시작한다.
---

# Autonomous Development Starter

이 스킬은 사용자가 **스킬 하나만 설치하고 `개발 시작`이라고 말해도 되는 단일 진입점**이다.
초기 설정과 실행 백엔드 선택을 사용자에게 떠넘기지 않는다. 프로젝트 증거와 사용자의 명시적 선호를 기준으로 필요한 값을 자동 결정한다.

## 최종 목표

한 번의 시작 흐름에서 다음 상태까지 만든다.

1. 프로젝트를 읽기 전용으로 진단한다.
2. 안전한 Git/비밀파일/출력물 정책을 설정한다.
3. 프로젝트별 실제 Quality Gate를 찾는다.
4. 공통 루프 문서와 상태 파일을 생성 또는 병합한다.
5. `chatgpt_remote` 또는 `local_cli` 실행 모드를 확정한다.
6. preflight와 1회 파일럿을 통과시킨다.
7. 사용자가 요청한 방식으로 반복 루프를 시작하거나 예약 가능한 상태로 만든다.

## 절대 안전 규칙

- 기존 사용자 변경을 reset/revert/clean하지 않는다.
- `.env`, PEM, token, secret, credential, 브라우저 로그인 데이터의 내용을 읽거나 출력하지 않는다.
- push, deploy, publish, 결제, 외부 메시지는 별도 명시적 승인 없이는 실행하지 않는다.
- `dangerously-bypass`, `yolo`, 무제한 권한 모드는 기본값으로 사용하지 않는다.
- 한 반복에는 대상 하나와 검증 가능한 수직 기능 하나만 처리한다.
- 한 프로젝트에서 Remote 루프와 CLI 루프를 동시에 실행하지 않는다.

## 입력 해석

사용자가 별도 옵션을 쓰지 않아도 동작해야 한다.

- `개발 시작` => `execution_mode: auto`, `auto_continue: true`.
- `Remote 연속 개발 시작`, `빈 시간 없이 개발`, `작업마다 새 ChatGPT 채팅으로 계속` => `chatgpt_remote` + Remote continuous orchestrator를 우선 검토한다.
- `Remote로 개발 시작`, `ChatGPT 예약으로 개발 시작` => `chatgpt_remote`.
- `CLI로 개발 시작` => `local_cli`.
- `Codex/Claude/Gemini/agy로 개발 시작` => `local_cli` + 해당 CLI 우선.
- 예약 시간/주기가 함께 주어지면 Remote 파일럿 PASS 후 ChatGPT Automation 생성까지 진행한다.
- 예약 시간/주기가 없으면 임의 시간을 만들지 않는다. Remote 모드는 즉시 1회 실행 가능한 상태까지 만들고 `READY_FOR_SCHEDULE`을 남긴다.

명시적 사용자 선택이 기존 `loop/EXECUTION.md`와 다르면 현재 loop가 IDLE인지 먼저 확인하고 안전하게 mode switch를 기록한다.

## Starter 실행 시 사용자 의견 반영 안내

프로젝트 루트를 확정하고 `docs/feedback/INBOX.md`를 사용할 수 있게 된 시점에, 사용자에게 아래 피드백 방법을 **한 번 짧게 안내한다.** 내부 파일을 직접 수정하도록 요구하지 않는다.

- `내 의견 반영: <내용>` / `다음 작업에 반영: <내용>` / `우선 작업: <내용>`처럼 자연어로 말하면 사용자 의견을 INBOX의 `READY` 작업으로 기록한다.
- `READY` 사용자 작업은 STATUS/DESIGN에서 자동 생성한 다음 작업보다 항상 우선한다.
- `보류` 요청은 해당 사용자 작업을 `PAUSED`로 바꾸고, 다시 진행하라는 명시적 요청 전에는 선택하지 않는다.
- 완료된 사용자 작업은 검증 후 `DONE`으로 바꾼다.
- Remote 연속 개발에서는 새 ChatGPT 채팅으로 넘어가도 INBOX가 사용자 의견의 영구 전달함 역할을 한다.
- 사용자가 "현재 작업에 바로 반영"이라고 명시하지 않았다면, 이미 RUNNING인 수직 작업을 중간에 깨지 말고 다음 반복부터 적용한다.

사용자에게 보여줄 안내는 장황한 내부 설명 대신 예시 중심으로 한다. 예: `개발 중 의견이 생기면 "내 의견 반영: 타워 업그레이드 때 외형도 바꿔줘"라고 말하면 다음 루프 최우선 작업으로 반영됩니다.`

## Phase 1. 읽기 전용 진단

1. 대상 프로젝트 루트를 확정한다.
2. 적용 가능한 `AGENTS.md`, README, manifest, 기존 loop/docs 상태를 읽는다.
3. Git 저장소/branch/HEAD/baseline/status를 확인한다.
4. package.json, pyproject.toml, Makefile 등에서 실제 test/lint/typecheck/build 명령을 찾는다.
5. 단일 앱, 모노레포, frontend, backend, fullstack, game, CLI, docs/data 중 가장 좁은 프로필을 선택한다.
6. 파일명과 경로만으로 비밀 가능 파일을 탐지하며 내용은 열지 않는다.

## Phase 2. 공통 초기 설정

먼저 `assets/common/`의 AGENTS, EXECUTION, PROJECTS, RUN_STATE, README를 공통 제어 규격으로 생성 또는 병합한다.
그 다음 선택된 mode의 assets에서 PROMPT, docs, runner/env 등 mode-specific 파일만 병합한다.
최종적으로 `AGENTS.md`, `docs/DESIGN.md`, `docs/STATUS.md`, `docs/feedback/INBOX.md`, `loop/EXECUTION.md`, `loop/PROMPT.md`, `loop/PROJECTS.md`, `loop/RUN_STATE.md`, `loop/README.md`를 보장한다.

병합 규칙:
- 기존 DESIGN/STATUS/AGENTS의 프로젝트 결정은 보존한다.
- INBOX는 사용자 소유이므로 기존 내용은 임의로 소비하거나 덮어쓰지 않는다.
- PROJECTS는 실제 앱 경로와 실제 gate만 기록한다.
- RUN_STATE가 최근 RUNNING이면 초기화하지 않고 중복 실행을 막는다.
- `.gitignore`에는 비밀/로그/runtime/build/dependency 산출물만 필요한 만큼 추가한다.
- 안전한 baseline이 없으면 `commit_allowed: false`로 시작한다.

## Phase 3. 실행 모드 선택

`references/execution-modes.md`를 읽고 다음 우선순위로 선택한다.

1. 사용자가 지정한 mode/CLI.
2. 기존 프로젝트의 EXECUTION 설정.
3. 현재 환경 증거.
4. `auto`이면 ChatGPT에서 AI Folder Remote를 사용할 수 있을 때 `chatgpt_remote`, 그렇지 않으면 검증된 `local_cli`.

선택 결과를 `loop/EXECUTION.md`와 `docs/STATUS.md`에 기록한다.

## Phase 4A. ChatGPT Remote 모드 설치

`assets/remote/` 템플릿을 프로젝트 사실과 병합한다.
실행 주체는 ChatGPT이며 Windows 작업은 AI Folder Remote로 직접 수행한다.
로컬 Codex/Claude/Gemini/agy를 이 모드에서 호출하지 않는다.

Remote 반복의 작업 선택 순서:
1. INBOX의 첫 READY 사용자 작업.
2. READY가 없고 `auto_continue: true`이면 STATUS의 다음 목표.
3. STATUS에도 없으면 DESIGN과 현재 구현 사이의 가장 작은 검증 가능한 간극.

자동 생성한 작업은 INBOX를 덮어쓰지 말고 RUN_STATE/STATUS 실행 기록에 `generated_task`로 남긴다.

Remote 예약 프롬프트의 핵심:
`AI Folder Remote로 대상 프로젝트의 loop/EXECUTION.md와 loop/PROMPT.md를 먼저 읽고, 선택 규칙에 따라 정확히 한 개의 수직 작업을 구현·검증·기록하라. local AI CLI, push, deploy는 금지한다.`

예약 시간/주기가 사용자 요청에 있으면 파일럿 PASS 후 ChatGPT Automation을 생성한다.
시간 정보가 없으면 Automation을 임의 생성하지 않고 `scheduler: READY_FOR_SCHEDULE`로 기록한다.

## Phase 4B. Local CLI 모드 설치

`assets/local/` 템플릿을 프로젝트에 병합하고 `loop/env.ps1`, `loop/loop.ps1`을 준비한다.
설치된 CLI를 `Get-Command`와 `--help` 같은 비파괴 명령으로 확인한다. 명령 구문은 현재 설치된 CLI help에서 검증한 뒤 `AGENT_CMD`를 작성한다.

CLI 우선순위는 사용자 지정 > 기존 EXECUTION 설정 > 검증 가능한 기본 후보 순이다.
기본 후보는 Codex, Claude, Gemini, agy이며 이것은 품질 순위가 아니라 결정적 fallback 순서다.

안전 기본값:
- Codex: `exec` 기반 non-interactive + workspace-write 수준. sandbox 우회 금지.
- Claude: `-p/--print` 기반 + edit 허용 permission mode. bypassPermissions 금지.
- Gemini: `-p/--prompt` 기반 + `auto_edit`. yolo 금지.
- agy: `--print` 기반 + `--mode accept-edits`. dangerously-skip-permissions 금지.

에이전트 프롬프트는 프로젝트의 `loop/PROMPT.md`를 전부 읽고 정확히 한 바퀴만 수행하도록 한다.
`loop.ps1`은 매 attempt마다 새 CLI 세션을 시작하고 Quality Gate, STOP, lock, retry, circuit breaker를 관리한다.

## Phase 5. Preflight와 파일럿

1. 프로젝트별 gate가 실제 존재하는 명령인지 재확인한다.
2. 비밀/생성물/runtime ignore 상태를 확인한다.
3. Remote면 대표 앱의 build/test-only preflight를 수행한다.
4. CLI면 `powershell -File loop/loop.ps1 -PreflightOnly`를 수행한다.
5. parser와 `git diff --check`를 가능한 범위에서 확인한다.
6. preflight PASS 후 실제 수직 작업 1개를 파일럿으로 수행한다.
7. 파일럿 실패 시 무한 루프/예약을 시작하지 않고 STATUS에 BLOCKED를 남긴다.

## Phase 6. 실제 시작

파일럿 PASS 후 선택된 모드만 활성화한다.

### chatgpt_remote
- 예약 정보가 있으면 ChatGPT Automation을 생성할 수 있다.
- 사용자가 연속 실행/즉시 다음 작업/작업마다 새 채팅을 원하고 Remote continuous capability가 있으면 scheduler 대신 Remote continuous orchestrator를 사용할 수 있다.
- Automation과 continuous orchestrator 모두 한 ChatGPT 채팅에는 한 작업만 수행한다. continuous orchestrator는 RUN_STATE 완료 handshake 후 즉시 새 채팅을 연다.
- `auto_continue: true`이면 사용자 READY 작업이 없어도 STATUS/DESIGN에서 다음 최소 작업을 선택한다.
- PC 또는 AI Folder Remote가 오프라인이면 소스 변경 없이 FAIL/BLOCKED로 종료한다.
- scheduler와 Remote continuous orchestrator를 동시에 활성화하지 않는다.

### local_cli
- 첫 파일럿은 `MAX_LOOPS=1`로 실행한다.
- 파일럿 PASS 뒤 사용자가 반복/자동 개발 시작을 요청한 상태라면 정상 loop 설정으로 실행한다.
- STOP 파일, 최대 실패 횟수, 회로 차단을 항상 유지한다.
- 실행 중인 CLI 루프가 있으면 두 번째 프로세스를 시작하지 않는다.

## Mode switch

Remote ↔ CLI 전환 시:
1. RUN_STATE가 IDLE인지 확인한다.
2. 기존 ChatGPT Automation, Remote continuous orchestrator 또는 로컬 loop process를 먼저 중지/비활성화한다.
3. runtime lock이 없는지 확인한다.
4. EXECUTION의 mode를 변경한다.
5. 새 mode preflight를 다시 수행한다.
6. STATUS에 전환 근거와 시각을 기록한다.

## 완료 보고

`STARTER PASS | PARTIAL | BLOCKED`로 시작하고 다음을 보고한다.
- 프로젝트 루트/프로필
- 선택된 execution mode와 선택 근거
- 선택된 CLI 또는 Remote 연결 상태
- 생성/병합한 루프 파일
- Git baseline/commit 정책
- 탐지한 Quality Gate
- preflight/파일럿 결과
- scheduler / Remote continuous orchestrator / local loop 활성화 상태

사용자에게 여러 내부 스킬 이름을 외우게 하지 않는다. 이후에도 `개발 시작`, `개발 계속`, `루프 중지`, `Remote로 전환`, `CLI로 전환` 같은 의도로 이 진입점이 적절한 하위 경로를 선택한다.

## 내부 참조

- 실행 모드 판단: `references/execution-modes.md`
- CLI별 안전한 headless 명령 기본형: `references/cli-command-templates.md`
- ChatGPT Automation 생성 계약: `references/chatgpt-automation.md`
- 사용자가 기억할 최소 명령: `references/usage.md`

CLI 명령은 참조 템플릿을 그대로 맹신하지 말고 현재 설치된 CLI의 `--help` 결과와 대조한 뒤 확정한다.

## Bootstrap interruption resilience

Bootstrap is transactional by phase, not by one long chat turn.

1. Install and maintain `loop/BOOTSTRAP_CHECKPOINT.md` from `assets/common/loop/BOOTSTRAP_CHECKPOINT.md`.
2. Before each mutating phase, read the checkpoint and verify the previous phase output.
3. After each phase, persist `last_completed`, `next_step`, and STATUS before starting more work.
4. If a tool response is missing or the chat turn is interrupted, do not assume failure or success; inspect the target files and resume from evidence.
5. Prefer small writes and short commands over long PowerShell one-liners.
6. On Windows PowerShell, avoid non-ASCII filename literals in `.ps1` source unless BOM encoding is guaranteed; discover such paths from ASCII parents when possible.
7. Bootstrap is complete only after parser checks, project preflight, Git safety validation, and checkpoint status `COMPLETE`.

These rules exist so a transient ChatGPT/tool interruption cannot force a full bootstrap restart or leave ambiguous partial state.

## Project Definition Gate (authoritative)

`개발 시작`은 곧바로 프로젝트 유형을 선택하거나 코드를 생성한다는 뜻이 아니다.
먼저 `references/project-intake.md`와 `assets/common/docs/PROJECT_INTAKE.md`를 사용해 프로젝트를 정의한다.

규칙:
1. 현재 요청에 목표, 유형, 사용자, 완료조건, 실행 방식이 충분히 있으면 질문을 생략하고 intake를 채운다.
2. 부족하면 한 번에 필요한 질문만 3~5개 묻는다. 이미 답한 내용은 다시 묻지 않는다.
3. Intake 완료 전에는 game/web/app/API/CLI/automation/data/docs 등 특정 프로필을 기본값으로 가정하지 않는다.
4. Intake 완료 후 가장 좁은 project profile을 선택하고 필요한 지식원만 연결한다.
5. 게임 위키, Godot, React 등 특정 도메인/기술은 해당 프로젝트 요구가 있을 때만 후보가 된다.

## Project LLM Wiki (default)

모든 신규 프로젝트는 `assets/common/docs/wiki/`를 기본 지식 계층으로 설치한다.
Karpathy LLM Wiki 패턴처럼 raw source는 불변으로 두고, LLM이 concepts/decisions/plans를 유지한다.
항상 `docs/wiki/index.md`를 먼저 읽고 최근 작업은 `log.md`에서 확인한다.
Intake와 기획서가 바뀌면 project-overview와 관련 Wiki 페이지, index, log를 함께 갱신한다.
Wiki 전체를 매번 읽지 말고 작업 관련 페이지 3~7개만 선택한다.
