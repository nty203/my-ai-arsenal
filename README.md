# AI Council (AI 평의회) 스킬 패키지

AI Council은 여러 대형 언어 모델(ChatGPT, Claude 등)에 동시에 질문을 전송하고, 그들의 답변을 백그라운드에서 자동으로 수집하여 종합적인 논의나 토론을 시킬 수 있는 **범용 자동화 스킬 패키지**입니다.

이 패키지는 Claude 3.5 Sonnet, Gemini 등 메인 AI 에이전트의 "서브 스킬"로 등록하여 사용하기에 최적화되어 있습니다.

## 🚀 주요 기능
- **다중 LLM 백그라운드 구동**: 메인 에이전트가 백그라운드(Session 0)에서 브라우저를 열어 다른 AI들의 의견을 수집합니다.
- **Cloudflare 방어벽 우회**: `undetected_chromedriver`와 사용자 세션 복제 방식을 활용하여 봇 차단을 완벽히 회피합니다.
- **JS ClipboardEvent 인젝션**: Selenium의 고질적인 한글(Non-ASCII) 입력 증발 버그와 OS 클립보드 미작동 버그를 피하기 위해, 브라우저 DOM에 가상의 붙여넣기 이벤트를 발생시키는 특수 기술이 적용되었습니다.

## 📦 설치 방법

### 1. 패키지 다운로드 및 의존성 설치
```bash
git clone https://github.com/사용자이름/ai-council-skill.git
cd ai-council-skill
pip install -r requirements.txt
```

### 2. 최초 1회 로그인 셋업 (Session 생성)
이 패키지는 귀찮은 매번 로그인을 방지하기 위해 쿠키/세션 파일을 저장합니다. 처음 사용하실 때는 아래 스크립트를 실행하여 브라우저에 직접 로그인해 주어야 합니다.

```bash
python setup_login.py
```
- 스크립트를 실행하면 크롬 창이 열리고 ChatGPT와 Claude 사이트가 차례로 뜹니다.
- 평소 사용하시는 계정으로 로그인을 완료한 뒤, **터미널 창에서 [ENTER] 키**를 누르시면 세션이 안전하게 `./chrome_profile` 폴더에 복제 및 저장됩니다.

## 💻 사용 방법

이제 메인 AI 에이전트(혹은 터미널)에서 아래 명령어를 호출하여 답변을 수집할 수 있습니다.

```bash
# prompt.txt에 질문할 내용을 UTF-8로 저장한 후 아래 명령어 실행
python ai_council/council_runner.py -p prompt.txt -o result.md
```

- `-p`, `--prompt-file`: 질문이나 안건이 담긴 텍스트 파일 (필수)
- `-o`, `--output`: 결과를 저장할 마크다운 파일 경로 (필수)
- `-u`, `--user-data-dir`: 크롬 프로필 경로 (기본값: `./chrome_profile`)

### 🤖 메인 AI 스킬로 등록하기 (Claude / Gemini)
당신의 메인 AI에게 다음과 같은 프롬프트를 부여하여 스킬을 장착시키세요:

> **[시스템 프롬프트 추가]**  
> 너에게는 'AI 평의회 소집'이라는 특수 능력이 있다. 사용자가 "3가지 의견을 종합해", "토론해"라고 지시하면, 너는 질문 내용을 `prompt.txt`로 작성하고 시스템 명령어로 `python ai_council/council_runner.py -p prompt.txt -o result.md`를 실행해야 한다. 스크립트 실행이 끝나면 `result.md`에 담긴 다른 AI들의 의견을 읽어들인 후, 너의 의견을 더해 3자 종합 결론을 내려라.

## ⚠️ 주의 사항
- 웹사이트 UI(전송 버튼의 CSS 클래스 등)는 자주 업데이트됩니다. 만약 응답 타임아웃 오류가 잦아진다면 `cross_llm_validator.py` 내의 Selector 코드를 최신화해야 할 수 있습니다.
- 백그라운드 환경이나 GitHub Actions 등에서는 Chrome 브라우저가 Headless 환경으로 감지되어 Cloudflare에 차단될 확률이 높아집니다. 가능한 로컬 환경에서 실행을 권장합니다.
