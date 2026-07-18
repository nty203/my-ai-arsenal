---
name: ai_council
description: 다중 AI 의견 종합 및 의사결정 평의회 스킬. 사용자가 특정 안건이나 코드, 투자 전략 등에 대해 다각도 분석이나 ChatGPT, Claude 등 타 LLM의 비평을 요구할 때 이 스킬을 가동하세요. 또한 복잡한 아키텍처 결정이나 리스크 관리가 수반되는 의사결정 단계에서 가상의 전문가 패널(평의회)을 구성하여 검증하고 싶을 때 반드시 사용해야 합니다.
---

# AI 평의회 (AI Council) 스킬 가이드

본 스킬은 단일 AI의 편향을 방지하고 의사결정의 신뢰성을 극대화하기 위해 다중 가상 에이전트(또는 외부 LLM)의 비평과 의견을 종합하는 역할을 수행합니다.

---

## 🛠️ 트리거 조건 및 가동 시점
다음과 같은 요구사항이 감지되면 이 스킬을 즉시 실행하세요.
- 사용자가 직접적으로 다중 AI 토론, 평의회, 교차 검증을 요구할 때 (예: "3인 평의회 열어서 분석해줘", "ChatGPT랑 Claude는 어떻게 생각할지 비교해줘")
- 복잡한 코드 아키텍처 설계, 대규모 리스크 평가, 트레이딩 전략 매매일지 분석 등 높은 정확성과 검증이 필요한 다차원적 문제 해결을 요청할 때

---

## 🚀 실행 절차 및 모드 선택
안건의 성격과 환경에 따라 다음 세 가지 모드 중 하나를 선택하여 진행하세요. 기본적으로 **Mode 1**을 우선 권장합니다.

### [Mode 1] 네이티브 서브에이전트 모드 (기본 권장)
내장 도구만으로 즉석 가상 평의회를 개최하는 방법입니다. 외부 API 키나 브라우저 로그인 상태에 의존하지 않으므로 가장 빠르고 안정적입니다.

1. **역할 정의**: 안건에 최적화된 서로 다른 관점의 가상 페르소나 2~3개를 구상합니다.
   * *예: [Quant Developer] 코드 최적화 및 기술적 타당성 분석*
   * *예: [Risk Manager] 잠재적 위험 요소 파악 및 한계점 비평*
   * *예: [Market Strategist] 시장 영향력 및 실용성 분석*
2. **서브에이전트 스폰**: `define_subagent` 도구를 호출하여 각 페르소나별 서브에이전트를 정의합니다.
3. **토론 요청 및 수집**: `invoke_subagent` 도구로 동일한 안건을 각 서브에이전트에 동시 발송하여 의견을 수집합니다.
4. **결과 종합**: 수집한 비평 결과를 취합하여 최종 보고서를 작성합니다.

### [Mode 2] 공식 API 모드 (외부 LLM 연동)
사용자가 실제 GPT-4o나 Claude 3.5 Sonnet의 실시간 응답을 요구할 때 사용합니다. (*주의: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` 환경변수가 설정되어 있어야 합니다.*)

1. 사용자의 질문 및 분석 안건을 텍스트 파일(`council_prompt.txt`)로 저장합니다.
2. 아래 명령어를 실행하여 공식 API를 통해 각 LLM의 응답을 받아 `council_result.md`에 저장합니다.
   ```powershell
   python C:\Users\tzero\.gemini\config\skills\ai_council\council_runner_api.py -p council_prompt.txt -o council_result.md
   ```
3. 생성된 `council_result.md`를 읽어 최종 분석에 활용합니다.

### [Mode 3] 셀레니움 브라우저 모드 (무료 웹 서비스 연동)
API 키가 없고 웹 브라우저 프로필을 이용해 ChatGPT 및 Claude 웹 무료 버전에 접근하고자 할 때 사용합니다. (*주의: 사전 로그인 세션 설정이 필요할 수 있습니다.*)

1. 로그인 상태 저장을 위해 웹 브라우저 프로필 설정이 필요하다면 먼저 아래 명령어를 실행하여 수동 로그인을 진행합니다.
   ```powershell
   python C:\Users\tzero\.gemini\config\skills\ai_council\setup_login.py
   ```
2. 사용자의 질문을 `council_prompt.txt`로 저장합니다.
3. 아래 명령어를 실행하여 웹 자동화 봇을 가동하고 결과를 `council_result.md`에 추출합니다.
   ```powershell
   python C:\Users\tzero\.gemini\config\skills\ai_council\council_runner.py -p council_prompt.txt -o council_result.md
   ```

---

## 📝 최종 보고서 템플릿
분석이 끝나면 반드시 아래 양식을 정확히 지켜 최종 결론을 사용자에게 제출하세요.

```markdown
# 🏛️ AI 평의회 종합 분석 보고서

## [AI별 의견 정리]
- **메인 에이전트 (Antigravity)**: [핵심 요점 및 초기 가설 설명]
- **참여 AI 1 (예: ChatGPT 또는 Quant 에이전트)**: [제시한 핵심 피드백 및 강점/약점 지적]
- **참여 AI 2 (예: Claude 또는 Risk 에이전트)**: [제시한 핵심 피드백 및 리스크 요인 지적]

## [교차 비평 및 논쟁 요약]
- **공통 합의점**: [모든 AI가 동의하는 핵심 사실이나 최선의 기법]
- **주요 대립점/이견**: [의견이 엇갈린 아키텍처나 기법 및 각각의 주장 이유]

## [최종 선택 방향 및 합의안]
- **결정된 실행 방향**: [합의안 또는 최종적으로 선택한 해결책]
- **선택의 구체적 근거**: [비평 검토 결과 및 참고한 RAG/컨텍스트 근거 제시]
- **추천 액션 아이템**:
  - `[ ]` [첫 번째 행동 단계]
  - `[ ]` [두 번째 행동 단계]
```

---

## 💡 실행 예시
**Input (User Prompt):**
> "이번에 작성한 Stock Screener 스케줄러 코드에 대해 평의회 열어서 리뷰해줘."

**Output (Agent Action):**
1. 안건 분석 후 `define_subagent`를 통해 `Quant_Reviewer`와 `Infrastructure_Reviewer` 정의
2. `invoke_subagent`를 사용하여 코드 평가 진행
3. 수집된 의견을 토대로 위의 **최종 보고서 템플릿**에 맞추어 종합 보고서 제공
