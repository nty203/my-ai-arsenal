# 🛠️ My AI Arsenal (Agent Skills Repo)

이 저장소는 다수의 AI 에이전트가 "스킬 설치해줘"라는 명령어로 손쉽게 플러그 앤 플레이(Plug & Play) 할 수 있도록 공식 스킬 규격을 준수하여 제작된 **개인 맞춤형 에이전트 무기고**입니다.

## 📁 디렉토리 구조

```text
my-ai-arsenal/
├── skills/           # Gemini & Claude 범용 공식 표준 규격 (SKILL.md)
│   └── ai_council/   # 다중 LLM 의견 종합 자동화 스킬
└── codex/            # Codex / Cursor 전용 규격
    └── ai_council/
```

## 🚀 에이전트별 스킬 설치 및 장착 가이드

### 🌌 1. Claude 및 Gemini (공용 표준)
Claude와 Gemini(Antigravity 등)는 [Agent Skills](http://agentskills.io) 표준인 `SKILL.md` 구조를 완벽히 지원합니다.
- **설치법**: 에이전트에게 **"이 깃허브 링크(`https://github.com/nty203/my-ai-arsenal/tree/master/skills/ai_council`)에 가서 스킬 설치해줘"** 라고 지시하면 끝입니다! 에이전트가 알아서 해당 폴더를 읽고 자신의 시스템에 스킬을 세팅합니다.

### 💻 2. Codex / Cursor (코딩 에이전트)
Cursor와 같은 코딩 에이전트들은 작업 중인 프로젝트의 규칙(.rules)으로 스킬을 인식합니다.
- **설치법**: `codex/ai_council/` 폴더를 통째로 다운받아 당신의 프로젝트 `.cursor/rules/` 폴더 등에 넣고, `instructions.md`의 내용을 시스템 프롬프트에 복사해 넣으세요.

---

## 🛠️ 공통 초기 세팅 (최초 1회 필수)
AI Council 스킬은 봇 차단을 우회하기 위해 사용자 본인의 세션을 복제하여 사용합니다. 스킬을 처음 내려받은 후, 터미널에서 아래 셋업 스크립트를 한 번 실행하여 ChatGPT와 Claude에 로그인해 주세요.

```bash
python setup_login.py
```
