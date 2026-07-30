---
name: notion_fable5_automation
description: Notion AI (Fable 5) 봇과 자동으로 대화하고, 생성된 아티팩트(파일)를 완벽하게 로컬로 추출하는 강력한 자동화 스킬입니다.
---

# 🤖 Notion Fable 5 Automation Skill

이 스킬은 노션 AI(Fable 5)를 브라우저 자동화(Playwright)를 통해 제어하여 다음과 같은 작업을 수행합니다.
1. 사용자 프롬프트를 전송하고 AI의 답변을 대기합니다.
2. AI가 생성한 결과물(아티팩트, 코드 블록, HTML 파일 등)을 무결점 스니핑 및 브루트포스 클릭 방식으로 찾아내어 로컬 파일 시스템(`docs/raw/`)으로 다운로드합니다.

## 📁 구성 요소

* `scripts/executor.ts`: 노션 AI 대화창을 열고 텍스트를 입력한 후 Fable 5 모델과 대화하는 주 실행기입니다.
* `scripts/extractor.ts`: 생성된 결과물(아티팩트, `.html` 파일 박스 등)을 감지하여 인라인 뷰어를 열고 자바스크립트로 Download 메뉴를 낚아채는 범용 추출기입니다.
* `scripts/package.json`: Playwright 의존성이 정의되어 있습니다.

## 🛠️ 사용 방법

Antigravity 에이전트로서 이 스킬을 활용할 때 다음 명령어를 실행하십시오. (실행 위치: `scripts/` 폴더 내부)

### 1. 의존성 설치
```powershell
npm install
```

### 2. 대화 시작 (Executor)
원하는 프롬프트 내용을 스크립트에 맞게 조정한 후, 다음을 실행합니다.
```powershell
npx tsx executor.ts
```

### 3. 결과물 추출 (Extractor)
대화가 끝난 페이지 URL이나 활성화된 창을 타겟팅하여 파일을 강제 다운로드합니다.
```powershell
npx tsx extractor.ts
```

## ⚠️ 유의 사항 (Agent Guidelines)

* **Extractor 동작 원리**: 이 추출기는 단순히 페이지를 긁는 것이 아닙니다. 파일 첨부 블록을 클릭하여 인라인 뷰어(Preview) 모달을 띄운 뒤, 순수 자바스크립트 엔진(`evaluate`)을 통해 화면 우상단 메뉴 버튼을 순차적으로 눌러 `Download` 이벤트를 강제로 발생시키는 무적의 브루트포스 로직입니다.
* **크롬 프로필 유지**: 스크립트는 `notion_chrome_profile`을 재사용하여 로그인 세션을 유지합니다.
