# Autonomous Loop Reliability Rules

이 문서는 실제 장시간 Remote 연속 개발 로그에서 반복된 실패를 일반 규칙으로 승격한 기준이다.
대화 내용은 지속 메모리가 아니다. `DESIGN`, `STATUS`, `INBOX`, `RUN_STATE`, claim/session 기록이 재시작 가능한 사실의 원본이다.

## 1. Fresh-session 원칙

- 각 iteration은 새 AI 세션/새 ChatGPT 채팅에서 시작한다.
- 이전 대화에 이어 쓰지 않는다. 긴 대화의 컨텍스트 드리프트가 다음 작업의 판단을 오염시키기 때문이다.
- 단, 새 세션은 새 작업을 뜻하지 않는다. `RUNNING`/`RECOVERING` claim이 있으면 그 exact task/run_id/claim만 복구한다.

## 2. Recovery adoption handshake

- 복구 세션은 claim을 새로 만들지 않는다.
- exact active task와 claim을 확인한 직후 첫 상태 기록으로 `heartbeat_at`을 갱신한다.
- 긴 읽기, 빌드, 테스트, 시각 QA 전후에도 설정된 heartbeat 간격 안에서 진행 신호를 갱신한다.
- orchestrator는 복구 중 claim 파일이 바뀌지 않는 것을 실패 신호로 해석하면 안 된다. 기존 claim을 유지하는 것이 정상이다.

## 3. Busy response 보호

- 프롬프트가 제출되고 ChatGPT 응답이 실제 busy이면, 단순한 벽시계 timeout만으로 stop 버튼을 누르거나 새 채팅을 열지 않는다.
- busy 응답 강제 중지는 명시적인 연결 끊김과 변경 없음이 함께 증명되는 경우에만 허용한다.
- 응답 watch window는 관찰 주기이지 작업 종료 제한이 아니다.
- UI가 idle이고 heartbeat도 stale일 때만 같은 claim의 recovery 새 세션을 검토한다.

## 4. STOP과 supervisor 의미

- `loop/STOP`은 graceful stop이다. 새 iteration을 시작하지 않되 이미 시작한 바퀴는 검증 가능한 checkpoint까지 마친다.
- 즉시 중단이 필요하면 별도 명시적 emergency/PAUSED 경로를 사용한다.
- supervisor는 비정상 crash를 재시작할 수 있지만 정상 `STOPPED`, `PROJECT_COMPLETE`, 사용자 STOP을 무조건 재시작하면 안 된다.
- 정상 종료와 비정상 종료를 구분하지 못하는 supervisor는 retry storm을 만든다.

## 5. 활성화 전 두 바퀴 실측

- 무한 루프, 로그인 자동 시작, scheduler를 켜기 전에 최소 두 iteration을 제한 실행한다.
- 두 로그에서 submit → start/adopt handshake → 구현/검증 → terminal closeout → UI idle 흐름을 직접 확인한다.
- timeout, 최대 턴, stale 기준은 감으로 정하지 않고 이 두 바퀴의 관측값에 여유를 더해 결정한다.
- 두 바퀴 중 하나라도 중복 세션, 미완료 claim, 비정상 종료를 보이면 자동 실행을 활성화하지 않는다.

## 6. 품질과 durable checkpoint

- 한 바퀴에는 검증 가능한 수직 기능 하나만 둔다.
- 자동 검사가 통과한 뒤 장시간 시각/수동 QA가 남았다면 VCS 정책이 허용하는 경우 candidate checkpoint를 남길 수 있다.
- 이 checkpoint는 완료 선언이 아니다. 시각 QA까지 통과해야 verified/final checkpoint다.
- 화면이 있는 결과는 실행 후 screenshot 또는 동등한 렌더 결과를 직접 읽고 판단한다. 코드 실행과 화면 품질은 별개의 게이트다.

## 7. 실패를 규칙으로 승격

- 같은 원인 또는 같은 사용자 지적이 두 번 발생하면 일회성 메모로 두지 말고 PROMPT/규칙으로 승격한다.
- 기계가 측정 가능한 규칙이면 test/lint/static check/guard script로 만든다.
- 반복 실패의 목표는 retry 횟수를 늘리는 것이 아니라 같은 종류의 실패가 다시 발생하지 않게 하는 것이다.

## 8. 로그는 판단 가능해야 한다

- poll마다 `healthy`를 append하지 않는다. 상태 전환, task/run_id 변화, child 재시작, 오류, 주기적 요약만 기록한다.
- 실시간 heartbeat는 작은 JSON/status 파일에 덮어쓰고, 사람이 읽는 로그는 transition 중심으로 유지한다.
- 장기 실행 로그는 날짜 또는 크기 기준으로 회전시켜 최근 두 iteration을 쉽게 검토할 수 있게 한다.

## 9. Local CLI state parity

- Local CLI uses the same RUN_STATE facts as Remote: active task, run_id, heartbeat, failure count, circuit, and project completion.
- A retry launched by the same runner is a fresh CLI session but must recover the exact active run/task when RUN_STATE remains RUNNING/RECOVERING.
- A newly started runner refuses an existing active state by default; `-RecoverExisting` is an operator recovery path, not a normal start mode.
- CLI process exit code 0 is not completion evidence by itself. The runner requires a changed terminal `last_result` and a non-active RUN_STATE, then re-runs registered Quality Gates.
- If independent post-session gates fail, stop instead of allowing the next unrelated task.
