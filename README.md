# 🛠️ My AI Arsenal

이 저장소는 다양한 AI 에이전트(Gemini, Claude, Cursor 등)가 공통으로 활용할 수 있는 **개인 맞춤형 에이전트 스킬 및 프로그램(Monorepo)** 모음집입니다.

## 📁 디렉토리 구조

```text
my-ai-arsenal/
├── skills/           # 실제 구동되는 파이썬 자동화 스크립트 모음
│   └── ai_council/   # 다중 LLM(ChatGPT, Claude) 의견 종합 스킬
├── setup/            # 초기 로그인 세션 생성 스크립트
└── agents/           # 각 에이전트에게 입력할 전용 지침서(명령어) 링크 모음
    ├── gemini/
    ├── claude/
    └── codex/
```

## 🚀 현재 보유 중인 스킬 목록

### 1. AI 평의회 (AI Council)
하나의 AI에 의존하지 않고, 백그라운드에서 ChatGPT와 Claude를 동시에 호출하여 답변을 수집하고 토론시키는 스킬입니다.

**[설치 및 초기 세팅]**
```bash
pip install -r requirements.txt
python setup/setup_login.py
```

**[에이전트별 장착 방법]**
본인이 사용하는 에이전트의 시스템 프롬프트(System Prompt)나 룰셋(Rules)에 아래 링크의 텍스트 내용을 복사해 넣으면 즉시 스킬을 사용할 수 있습니다.
- 🌌 **Gemini (Antigravity)**: [agents/gemini/ai_council.md](agents/gemini/ai_council.md)
- 🧠 **Claude (Cline 등)**: [agents/claude/ai_council.md](agents/claude/ai_council.md)
- 💻 **Cursor (Codex)**: [agents/codex/ai_council.md](agents/codex/ai_council.md)

---
*추가적인 스킬이 개발될 때마다 이 저장소에 업데이트됩니다.*
