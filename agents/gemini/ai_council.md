---
name: ai_council
description: 사용자가 질문이나 토론을 요구할 때 ChatGPT와 Claude를 백그라운드에서 동시에 호출하여 다중 AI 의견을 수집하고, 최종 결론을 종합하는 스킬.
---

# AI 평의회 (AI Council) 작동 지침

이 스킬은 사용자가 특정 안건에 대해 다각도의 분석을 원하거나 "토론해봐"라고 지시할 때 활성화됩니다. 당신(Gemini/Antigravity)은 평의회의 의장으로서 다음 단계를 수행해야 합니다.

## 1. 프롬프트 생성
사용자의 질문이나 토론 주제를 명확하게 정리하여 텍스트 파일(`council_prompt.txt`)로 프로젝트 루트에 저장합니다. (반드시 UTF-8 인코딩 사용)

## 2. 평의회 소집 (스크립트 실행)
작성한 프롬프트를 바탕으로 아래의 명령어를 통해 2명의 외부 의원(ChatGPT, Claude)을 백그라운드에서 호출합니다.
```bash
python skills/ai_council/council_runner.py -p council_prompt.txt -o council_result.md
```
(초기 셋업이 안 되어 크롬 프로필 에러가 발생한다면 사용자에게 `python setup/setup_login.py`를 먼저 실행하도록 안내하세요.)

## 3. 의견 수렴 및 토론 진행
스크립트 실행이 완료되면 `council_result.md`에 저장된 두 의원의 답변을 읽습니다.
만약 사용자가 "토론(Debate)"을 요구한 경우, 양쪽의 1차 답변을 서로 비판하도록 하는 2차 프롬프트를 작성하여 스크립트를 한 번 더 실행합니다.

## 4. 최종 종합 (Synthesis)
당신(Gemini)의 고유한 분석력과 통찰력을 더해, ChatGPT와 Claude의 의견을 종합한 **최종 3자 종합 결론(Tripartite Synthesis)** 아티팩트를 작성하여 사용자에게 보고합니다.
