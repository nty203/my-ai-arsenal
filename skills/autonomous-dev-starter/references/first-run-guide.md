# First Run Guide

After bootstrap has enough facts to name the project root and execution mode, show the user a short guide like this, adapted to the actual project.

## Required user-facing points

1. **Start/continue**: say `개발 계속`; for immediate fresh-chat chaining say `Remote 연속 개발 시작`.
2. **Give priority feedback**: say `내 의견 반영: ...` or `우선 작업: ...`; it becomes READY and outranks automatic work.
3. **How autonomy works**: user/planned work is completed first; only then does the loop evaluate evidence-backed improvements one at a time.
4. **Control**: `보류`, `재개`, `취소`, `루프 중지`, `Remote로 전환`, `CLI로 전환` are accepted as natural-language controls.
5. **Memory**: Remote fresh chats use INBOX/STATUS/RUN_STATE/Wiki as persistent project memory.
6. **Finish**: when completion signals and gates pass and no valuable improvement remains, the project becomes PROJECT_COMPLETE instead of looping forever.

## Example concise guide

`Starter 준비 완료. 현재 모드는 <mode>입니다. 평소에는 "개발 계속"이라고 하면 되고, 연속으로 돌리려면 "Remote 연속 개발 시작"이라고 하세요. 개발 중 의견은 "내 의견 반영: <내용>"이라고 말하면 다음 최우선 작업으로 저장됩니다. 루프는 사용자/계획 작업을 먼저 끝낸 뒤, 할 일이 없을 때만 테스트·UX·성능 등 실제 근거가 있는 개선점을 스스로 찾아 하나씩 검증합니다. "루프 중지", "보류", "재개"도 바로 사용할 수 있습니다. 완료 조건을 모두 만족하고 가치 있는 개선이 없으면 PROJECT_COMPLETE로 자동 종료합니다.`

Keep this guide short. Do not dump internal schemas unless the user asks.
