# 🛠️ My AI Arsenal

이 저장소는 다양한 AI 에이전트(Gemini, Claude, Cursor 등)에 곧바로 복사해서 붙여넣을 수 있는 **'Plug & Play' 네이티브 스킬 패키지 모음집**입니다.

## 🚀 플러그 앤 플레이(Plug & Play) 방식이란?
기존의 복잡한 스크립트 경로 설정을 할 필요가 없습니다. 본인이 사용하는 에이전트의 폴더를 복사(Drag & Drop)해서 본인의 프로젝트에 넣기만 하면, 각 에이전트가 가장 좋아하는 네이티브(Native) 폴더 규격에 맞게 즉시 스킬이 연동됩니다.

## 📁 에이전트별 장착 가이드

### 🌌 1. Gemini (Antigravity) 전용
Gemini(Antigravity)는 `.agents/skills/` 폴더를 자동으로 감지합니다.
- **설치법**: `for_gemini/.agents` 폴더를 복사하여 당신의 프로젝트 루트 경로에 그대로 붙여넣습니다.
- **사용법**: Gemini에게 "AI 평의회 소집해줘"라고 말하면 알아서 `SKILL.md`를 읽고 백그라운드 скрип트까지 자동 실행합니다.

### 🧠 2. Claude (Cline / Desktop) 전용
Claude 스킬 관리 관행에 맞춘 독립 폴더입니다.
- **설치법**: `for_claude/skills` 폴더를 복사하여 당신의 프로젝트 루트 경로에 그대로 붙여넣습니다.
- **사용법**: Claude의 프롬프트 창이나 시스템 프롬프트(Instructions) 영역에 `instructions.md`의 내용을 복사해서 먹여두면, Claude가 파이썬 코드를 백그라운드에서 알아서 실행하고 결과를 가져옵니다.

### 💻 3. Cursor / Codex (코딩 에이전트) 전용
Cursor는 프로젝트 내의 `.cursor/rules/` 디렉토리를 룰셋으로 읽어들입니다.
- **설치법**: `for_cursor/.cursor` 폴더와 `for_cursor/scripts` 폴더를 복사하여 당신의 프로젝트 루트에 붙여넣습니다.
- **사용법**: 코드 리뷰나 아키텍처 논의 중 "AI 평의회의 의견도 들어봐"라고 하면 Cursor가 알아서 백그라운드 봇을 돌리고 최적의 코드를 종합 제안합니다.

---

## 🛠️ 공통 초기 세팅 (최초 1회 필수)
각 스킬 패키지 내부에는 `setup_login.py`가 동봉되어 있습니다. 스킬을 처음 장착한 후, 터미널에서 셋업 스크립트를 한 번 실행하여 ChatGPT와 Claude에 로그인해 주어야 봇 차단 방어벽을 피할 수 있습니다.

```bash
# 예시: Gemini 환경에 복사한 경우
python .agents/skills/ai_council/setup_login.py
```
