# 🛠️ My AI Arsenal (Agent Skills Repo)

이 저장소는 다양한 AI 에이전트(Claude Code, Antigravity/Gemini, Cursor, Codex 등)가 필요할 때 손쉽게 플러그 앤 플레이(Plug & Play)로 불러와 사용할 수 있도록 **Agent Skills 표준 규격(`SKILL.md`)**을 준수하여 제작된 **개인 맞춤형 에이전트 무기고**입니다.

---

## ⚡ 수록 스킬 (Available Skills)

### 1. 🏛️ `ai_council` — AI 평의회 스킬
> **"단일 AI의 편향을 극복하는 다중 LLM 교차 검증 및 비평 시스템"**

- **경로**: [`skills/ai_council/SKILL.md`](skills/ai_council/SKILL.md)
- **핵심 역할**:
  - 복잡한 아키텍처 설계, 투자/트레이딩 전략, 리스크 평가 등 높은 검증이 필요한 문제에 대해 다각도 분석 및 비평 수행
  - ChatGPT(수익/공격적 관점), Claude(리스크/방어적 관점), 현재 에이전트(중재/시스템 설계)의 입장을 3자 토론으로 전개하여 합의안 도출
- **지원 실행 모드**:
  1. **Mode 1 (단일 에이전트 자아분열)**: 외부 연동 없이 텍스트 내에서 3자 난상 토론 시뮬레이션 (빠르고 오류 없음)
  2. **Mode 2 (네이티브 서브에이전트)**: 서브에이전트를 동적 스폰하여 가상 전문가 패널 토론
  3. **Mode 3 (공식 API 연동)**: OpenAI / Anthropic API를 직접 호출하여 실제 답변 교차 분석
  4. **Mode 4 (셀레니움 웹 연동)**: 무료 웹 브라우저 프로필을 이용해 대화형 세션에서 토론 가동

---

### 2. 🚀 `run-project` — 프로젝트 마스터 파이프라인
> **"컨텍스트 수집부터 루브릭 채점 및 자동 검증까지, 10단계 프로젝트 성공 공식"**

- **경로**: [`skills/run-project/SKILL.md`](skills/run-project/SKILL.md)
- **핵심 역할**:
  - 어떤 프로젝트든 **[스캐폴딩 → 컨텍스트 주입 → 심사자 제작 → 전수 리서치 → 문제 정의 → 솔루션 플래닝 → 핸드오프 → 구현+자동검증 → 휴먼 테이스트 → 패키징]**의 10단계 파이프라인으로 체계화하여 완수.
  - 구현 시작 전 **채점기(루브릭 2종: JUDGE_HUMAN, JUDGE_AI)**와 **문제 정의**를 먼저 확립하여 엉뚱한 산출물이 나오는 위험을 원천 차단.
  - 에이전트의 셀프 개선/검증 루프(목표 점수 도달 시까지 최대 7라운드)를 돌려 압도적 완성도 달성.
- **10단계 핵심 파이프라인**:
  - **Phase A. 준비**: Step 0 스캐폴딩 ➔ Step 1 컨텍스트 주입+인터뷰 ➔ Step 2 심사자 제작 (JUDGE_HUMAN / JUDGE_AI)
  - **Phase B. 탐색**: Step 3 전수 리서치 ➔ Step 4 문제 정의 (전수 채점 & 스코핑 상향) ➔ Step 5 솔루션 플래닝
  - **Phase C. 실행**: Step 6 핸드오프 (세션 분리) ➔ Step 7 구현 + 자동 검증 루프 ➔ Step 8 휴먼 테이스트 (취향 검증) ➔ Step 9 패키징

---

## 📁 디렉토리 구조

```text
my-ai-arsenal/
├── skills/           # Gemini & Claude 범용 공식 표준 규격 (SKILL.md)
│   ├── ai_council/   # 다중 LLM 의견 종합 및 의사결정 평의회 스킬
│   └── run-project/  # 프로젝트 10단계 마스터 파이프라인 스킬
└── codex/            # Codex / Cursor 전용 규격
    └── ai_council/
```

---

## 🚀 에이전트별 스킬 설치 및 장착 가이드

### 🌌 1. Claude 및 Gemini (공용 표준)
Claude와 Gemini(Antigravity 등)는 [Agent Skills](http://agentskills.io) 표준인 `SKILL.md` 구조를 완벽히 지원합니다.
- **설치법**: 에이전트에게 아래 깃허브 경로를 주면서 **"스킬 설치해줘"** 라고 지시하세요.
  - `ai_council`: `https://github.com/nty203/my-ai-arsenal/tree/master/skills/ai_council`
  - `run-project`: `https://github.com/nty203/my-ai-arsenal/tree/master/skills/run-project`

### 💻 2. Codex / Cursor (코딩 에이전트)
- **설치법**: 각 스킬 폴더(`skills/<skill-name>/`)의 `SKILL.md` 내용을 프로젝트의 `.cursor/rules/` 또는 시스템 프롬프트에 등록하여 사용합니다.

---

## 🛠️ 공통 세팅 (선택)
`ai_council` 스킬의 API/셀레니움 연동을 사용할 경우, 필요 시 로그인 및 환경 변수(`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`)를 세팅할 수 있습니다.
```bash
python setup_login.py
```
