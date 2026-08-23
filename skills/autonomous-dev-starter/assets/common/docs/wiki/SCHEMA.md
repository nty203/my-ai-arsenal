# Project LLM Wiki Schema

이 Wiki는 Karpathy의 LLM Wiki 패턴을 프로젝트 개발용으로 적용한다.

## Layers

1. `raw/`: 사용자가 제공한 원본 자료. LLM이 임의 수정하지 않는다.
2. `concepts/`, `decisions/`, `plans/`: LLM이 유지하는 누적 Wiki.
3. `SCHEMA.md` + `AGENTS.md`: 구조와 운영 규칙.

## Navigation

- 모든 프로젝트 탐색은 `index.md`부터 시작한다.
- 최근 변경은 `log.md` 마지막 항목에서 확인한다.
- 실제 작업에는 관련 Wiki 3~7개만 읽는다.
- 좋은 분석/결론은 재사용 가치가 있으면 Wiki에 다시 저장한다.

## Maintenance

- 기획 변경은 관련 `plans/` 페이지와 index를 갱신한다.
- 기술/범위 선택은 `decisions/`에 이유와 대안을 기록한다.
- 핵심 개념은 `concepts/`에 병합하고 중복 페이지를 피한다.
- 충돌 정보는 덮어쓰지 않고 contradiction으로 표시한다.
- 가능한 경우 페이지마다 `[[관련_페이지]]` 링크를 둔다.
- 모든 ingest/query/lint/중요 변경은 `log.md`에 append한다.
