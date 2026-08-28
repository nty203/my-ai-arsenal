# 사용 가이드

사용자는 `autonomous-dev-starter` 하나만 기억하면 된다. 내부 루프 파일을 직접 편집할 필요가 없다.

## 처음 시작할 때

가장 간단한 명령은 `개발 시작`이다. Starter가 프로젝트 구조, 기존 VCS(Git/SVN), Quality Gate, 실행 모드를 진단하고 새 세션 기준의 제한된 파일럿 2회를 준비한다. 두 로그를 검토하기 전에는 무한 루프나 로그인 자동 시작을 활성화하지 않는다.

원하는 실행 방식이 있으면 처음부터 말할 수 있다.
- `ChatGPT Remote로 개발 시작` — ChatGPT + AI Folder Remote
- `Remote 연속 개발 시작` — 작업 하나가 끝날 때마다 새 ChatGPT 채팅으로 즉시 다음 작업
- `매일 오후 12시에 ChatGPT Remote로 개발 시작` — 파일럿 PASS 후 예약 실행
- `CLI로 개발 시작` / `Codex로 개발 시작` / `Claude로 개발 시작` — 검증된 로컬 headless CLI 사용

Starter는 첫 실행에서 현재 모드, 자동 개선 여부, 의견 넣는 법, 중지/재개 방법, 완료 기준을 짧게 안내해야 한다.

## 평소 사용하는 명령

- `개발 계속` — 저장된 방식으로 다음 iteration 1회 진행
- `Remote 연속 개발 시작` — 연속 루프 시작
- `Remote 연속 개발 상태` — 현재 상태만 확인
- `루프 중지` — 새 iteration 시작을 막는다. 이미 시작된 iteration은 안전한 closeout까지 마친 뒤 중지한다(긴급 PAUSED는 별도).
- `Remote 연속 개발 재개` / `개발 재개` — 중지 또는 PROJECT_COMPLETE 이후 새 작업과 함께 다시 활성화
- `Remote로 전환` / `CLI로 전환` — 안전하게 실행 backend 변경

## 내 의견을 최우선으로 넣기

자연어로 말하면 된다.
- `내 의견 반영: 타워 업그레이드 때 외형도 바꿔줘`
- `다음 작업에 반영: 로그인 오류 메시지를 더 명확하게 해줘`
- `우선 작업: 저장 데이터 마이그레이션부터 처리해줘`
- `<작업> 보류` / `<작업> 다시 진행` / `<작업> 취소`

READY 사용자 작업은 자동 생성 작업보다 항상 우선한다. 이미 RUNNING인 수직 작업은 사용자가 즉시 반영을 명시하지 않는 한 안전하게 끝낸 뒤 다음 iteration부터 적용한다.

## 루프가 일을 고르는 순서

1. 사용자 READY 작업
2. 실패한 테스트/회귀/블로커 복구
3. TASK_BOARD/STATUS의 계획 작업
4. DESIGN의 미완료 필수 범위
5. 위 작업이 없을 때만 자율 개선

자율 개선은 최대 몇 개의 후보를 평가한 뒤 실제 근거와 검증 방법이 가장 강한 1개만 수행한다. 단순 취향, 의미 없는 리팩터링, 작업을 계속하기 위한 작업은 만들지 않는다.

## 자율 개선은 무엇을 보는가

예: 오류/실패 테스트, UX 마찰, 성능 저하, 접근성 문제, 테스트 공백, 반복되는 장애, 유지보수 위험. 변경 후 테스트·벤치마크·화면 흐름 등으로 좋아졌는지 검증할 수 있어야 한다.

## 언제 끝나는가

필수 계획 작업이 모두 끝나고, DESIGN의 완료 조건과 필수 Quality Gate가 PASS이며, Critical/High blocker가 없고, 증거 기반으로 가치 있는 개선 후보도 없으면 `PROJECT_COMPLETE`가 된다. 이 상태에서는 연속 루프가 새 일을 억지로 만들지 않는다. 새 사용자 작업을 넣거나 `개발 재개`를 말하면 다시 ACTIVE로 돌아갈 수 있다.

## Remote 연속 개발의 기억

각 작업은 새 ChatGPT 채팅에서 실행될 수 있다. 대화 기억 대신 `INBOX`, `STATUS`, `RUN_STATE`, Wiki가 프로젝트의 지속 메모리 역할을 한다. 따라서 사용자 의견과 검증 결과가 다음 채팅에도 전달된다.

Remote continuous의 기본 구현은 스킬에 포함된 persistent Chrome DOM 드라이버다. 별도 자동화 프로필로 로그인한 뒤 `loop/browser-driver/browser-ui.ps1 -Action Probe`가 Chat 모드와 `AI Folder Remote` 토큰을 비제출 상태로 확인해야 실제 루프를 시작한다. 루프는 한 브라우저 탭을 재사용하되 작업마다 `/` 새 채팅으로 이동하며, 현재 응답과 RUN_STATE가 모두 끝나기 전에는 다음 채팅을 열지 않는다. 브라우저 검증이 불가능한 환경에서만 기존 Windows 앱 드라이버를 fallback으로 사용한다.

## CLI recovery note

Local CLI mode now keeps the same durable RUN_STATE handoff as Remote mode. Normal runs refuse an already active RUNNING/RECOVERING state. After verifying the old CLI process is no longer running, `loop/loop.ps1 -RecoverExisting` resumes that exact run_id/active_task; retries inside one loop do this automatically after a crashed attempt.
