---
name: notionAI
description: Notion AI (Fable 5) 봇과 자동으로 대화하고, 생성된 아티팩트 페이지를 MCP 없이 브라우저에서 직접 마크다운으로 추출하는 자동화 스킬입니다.
---

# 🤖 notionAI Skill

Playwright로 Notion AI를 제어해 프롬프트를 보내고, **AI가 만든 아티팩트 페이지를
MCP 의존 없이 브라우저 DOM에서 직접 마크다운으로 추출**한다.

> **왜 MCP를 안 쓰는가**: Notion MCP가 없는 환경에서는 결과물을 아예 못 가져오게 된다.
> 이 스킬은 이미 로그인된 Playwright 세션의 DOM을 그대로 읽으므로 MCP 유무와 무관하게 동작한다.

## 📁 구성 요소

| 파일 | 역할 |
|---|---|
| `scripts/executor.ts` | 주 실행기. `runPrompt()`(모델 선택 → 전송 → 응답 대기 → 아티팩트 추출)와, 브라우저를 직접 열고 닫는 CLI 진입점 `askNotionAi()`를 함께 export |
| `scripts/notionUi.ts` | 모델 드롭다운 조작 공용 함수 (`listAvailableModels`, `selectModel`). executor.ts/listModels.ts/interactive.ts가 공유 |
| `scripts/listModels.ts` | 프롬프트 전송 전에 현재 선택 가능한 모델 목록만 조회하는 단독 CLI (브라우저를 열었다 바로 닫음) |
| `scripts/interactive.ts` | **브라우저를 한 번만 띄운 채로** 모델 목록 조회 → 사람이 고를 때까지 대기 → 즉시 그 모델로 진행까지 이어가는 CLI. 매번 브라우저를 여닫는 게 아니라 세션을 유지하고 싶을 때 이걸 쓴다 |
| `scripts/pageExtract.ts` | Notion 페이지 DOM → 마크다운 변환기 + 아티팩트 링크 탐지 |
| `scripts/fetchPage.ts` | 페이지 URL만으로 마크다운 추출하는 단독 CLI |
| `scripts/session.ts` | 로그인 세션 보장/판정 |
| `scripts/login.ts` | 최초 1회 로그인용 CLI |
| `scripts/extractor.ts` | (구) 첨부파일 다운로드용 추출기. HTML/파일 블록 다운로드가 필요할 때만 사용 |

## 🛠️ 사용 방법

### 0. 의존성 설치 (최초 1회)
```bash
cd "C:/Users/nam9n/.claude/skills/notionAI/scripts" && npm install && npx playwright install chromium
```

### 0-1. 로그인 (최초 1회, 또는 세션 만료 시)

로그인은 크롬 프로필(`notion_chrome_profile`)에 저장되어 이후 자동 유지된다.
스크립트는 자격증명을 다루지 않으며, 사람이 브라우저에서 직접 로그인한다.

```bash
cd "C:/Users/nam9n/.claude/skills/notionAI/scripts" && npx tsx login.ts
```

`executor.ts`는 미로그인 상태를 감지하면 **브라우저를 띄운 채 로그인을 기다린다**(기본 5분).
`fetchPage.ts`는 headless라 로그인이 불가능하므로 **2초 만에 위 명령을 안내하며 실패**한다.

### 1. 모델 선택 (프롬프트 전송 전, 매번 권장)

Notion 쪽 모델 라인업이 수시로 바뀌므로 모델명을 하드코딩해서 넘기지 말고,
**매번 실제 드롭다운을 열어 지금 고를 수 있는 모델을 조회한 뒤** 사용자에게 고르게 한다.

**권장 방법 — `interactive.ts` (브라우저를 한 번만 띄운 채 이어감):**

```bash
cd "C:/Users/nam9n/.claude/skills/notionAI/scripts" && npx tsx interactive.ts "<프롬프트>"
```

절차 (에이전트 관점):
1. 위 명령을 **백그라운드로** 실행한다 (브라우저를 열고 로그인 확인 → 모델 목록 조회 →
   `MODELS_JSON:[...]` 한 줄을 stdout에 찍고 **브라우저를 닫지 않은 채** 대기 상태로 들어간다).
2. 그 출력 줄이 나올 때까지 백그라운드 출력을 확인한다 (Monitor로 `MODELS_JSON:`을 grep하면 편함).
3. 목록을 `AskUserQuestion` 같은 실제 선택 UI로 사용자에게 보여주고 고르게 한다.
4. 고른 모델 라벨을 `{"model": "<라벨>"}` 형태로 `scripts/model_choice.json`에 쓴다
   (파일명은 실행 시 두 번째 인자로 바꿀 수 있음). 대기 중이던 프로세스가 파일을 감지하는 즉시
   **브라우저 재시작 없이** 그 모델로 선택 → 프롬프트 입력 → 전송 → 응답/아티팩트 추출까지 이어간다.
5. 완료되면 `last_result.txt`(+아티팩트가 있으면 `last_page.md`/`last_artifact.json`)가 저장된다.

**단독 조회만 필요할 때** (매번 브라우저를 새로 열어도 상관없는 경우):
```bash
cd "C:/Users/nam9n/.claude/skills/notionAI/scripts" && npx tsx listModels.ts
```
JSON 배열로 출력된다 (예: `["Auto ...", "Opus 5", "GPT-5.6 Sol", "Sonnet 5", "Fable 5 Beta", "Gemini 3.6 Flash", ...]`).

**옵션 우선순위 (사용자 확정, 2026-08-12):**
1순위(최상단 노출): `GPT * Sol` 계열, `Fable *` 계열
2순위: `Opus *` 계열, `GPT * Terra` 계열
그 외(Auto, GPT Luna, Kimi, Gemini, Grok, DeepSeek, GLM 등)는 "기타"로 자유 입력받는다.
이름 뒤 버전 숫자는 바뀔 수 있으므로 정확한 문자열이 아니라 **패턴(Sol/Terra/Fable/Opus)** 기준으로 우선순위를 매길 것.
(`AskUserQuestion`은 보통 옵션 4개까지만 노출되므로, 우선순위 낮은 항목은 "기타" 자유 입력으로 받는다.)

고른 라벨을 그대로 `executor.ts` CLI의 두 번째 인자(또는 `interactive.ts`의 답변 파일)에 넘기면 된다.

### 2. 대화 실행 + 결과물 추출 (기본)

인자 순서: `<프롬프트 또는 @파일경로> [모델명] [이미지경로]`

```bash
cd "C:/Users/nam9n/.claude/skills/notionAI/scripts" && npx tsx executor.ts "질문 내용" "Fable 5"
```

프롬프트가 길면 파일로 넘긴다 (셸 이스케이프 문제 회피):

```bash
cd "C:/Users/nam9n/.claude/skills/notionAI/scripts" && npx tsx executor.ts "@C:/path/to/prompt.txt" "Fable 5"
```

**생성되는 파일** (스크립트 디렉토리):

| 파일 | 내용 |
|---|---|
| `last_result.txt` | 채팅 화면 응답 텍스트 |
| `last_page.md` | **아티팩트 페이지 본문 마크다운** (표/체크박스/코드블록 포함) |
| `last_artifact.json` | 아티팩트 페이지 URL·제목 |
| `last_response.png` | 응답 시점 전체 스크린샷 |

### 3. 페이지 URL로 직접 추출 (단독)

이미 아는 Notion 페이지를 마크다운으로 가져올 때:

```bash
cd "C:/Users/nam9n/.claude/skills/notionAI/scripts" && npx tsx fetchPage.ts "https://app.notion.com/p/xxxx" out.md
```

## ✅ 동작 보증 장치

* **모델 목록 실측 조회**: 모델명을 하드코딩해 추측하지 않고 `listModels.ts`로 그 순간
  실제 드롭다운에 뜨는 항목을 읽어온 뒤 사용자에게 고르게 한다. Notion 쪽 라인업이
  수시로 바뀌어서 생기는 "존재하지 않는 모델명 지정 → 실패" 문제를 구조적으로 차단.
* **모델 선택 검증**: 선택 후 버튼 라벨을 다시 읽어 목표 모델이 맞는지 확인하고,
  아니면 **즉시 예외로 실패**한다. 조용히 Auto 모델 답변을 받아오는 사고를 구조적으로 차단.
* **입력창 초기화**: 영속 프로필에 남은 이전 초안을 지우고 입력한다 (프롬프트 오염 방지).
* **전송 검증**: 전송 후 입력창이 비워졌는지 확인해 실패를 경고한다.
* **아티팩트 탐색은 "페이지 생성 신호"가 있을 때만 시도한다**: 응답 생성 중 텍스트에
  "Creating page"/"Vibing"이 뜬 적이 있을 때만 `findArtifactLink`를 호출한다. 잡담성
  응답("테스트" 등)에서 채팅/사이드바의 무관한 기존 페이지(멘션 링크, "My Tasks" 등)를
  아티팩트로 오탐하던 근본 원인을 차단한다 (좌표/클래스명 휴리스틱보다 신뢰도 높음).

## ⚠️ 유의 사항 — Notion DOM의 함정 (실측 기록)

이 스킬을 고칠 때 반드시 알아야 할 것들:

* **`<button>` 태그가 없다.** Notion UI는 전부 `div[role="button"]`이다.
  `document.querySelectorAll('button').length === 0`. 반드시 `data-testid`로 잡을 것.

  | 용도 | 셀렉터 |
  |---|---|
  | 모델 선택 | `[data-testid="unified-chat-model-button"]` |
  | 전송 | `[data-testid="agent-send-message-button"]` |
  | 입력창 | `div[contenteditable="true"]` |

* **메뉴 항목 텍스트에 공백이 없다.** "Fable 5 Beta"의 `textContent`는 `"Fable5Beta"`다.
  각 단어가 별도 자식 요소라서 붙는다. → 공백 제거 후 부분 매칭할 것 (`=== 'Fable 5'`는 절대 성립 안 함).

* **모델 메뉴는 스크롤 드롭다운이다.** 목표 항목이 보이는 영역 밖으로 클리핑되면
  좌표 클릭이 메뉴 바깥을 눌러 조용히 무시된다.
  → `scrollIntoView` 후 `document.elementFromPoint`로 실제 클릭 대상인지 확인하고 클릭.

* **선택 후 버튼 라벨이 메뉴 항목 라벨과 다를 수 있다.** 메뉴엔 "Fable 5 Beta"로 나와도
  선택 후 버튼엔 "Fable 5"처럼 태그가 생략된 축약형이 표시된다.
  → 검증은 한쪽만 `includes`로 보지 말고 **양방향 부분일치**(`a.includes(b) || b.includes(a)`)로
  판정할 것 (`notionUi.ts`의 `matches()`). 편도 매칭은 정상 선택인데도 검증 실패로 오탐한다.

* **표에 `role="row"`가 없다.** 셀(`.notion-table-cell-text`)만 존재하므로
  **y좌표로 묶어 행을 복원**해야 한다.

* **to_do 체크 상태에 `aria-checked`가 없다.**
  본문의 `text-decoration: line-through` 여부로 판정한다.

* **블록은 중첩된다.** 블록의 자기 텍스트만 얻으려면
  복제본에서 자손 `[data-block-id]`를 제거하고 읽어야 한다.

* **Windows에서 "직접 실행 여부" 판정은 `pathToFileURL`로 할 것.** `executor.ts`는 다른
  스크립트(`interactive.ts`)가 `runPrompt`만 가져다 쓰려고 import해도 파일 하단의 CLI
  블록까지 같이 실행되는 걸 막으려고 `isMainModule` 가드를 쓴다. 이걸
  `` `file://${process.argv[1]}` `` 식으로 손으로 문자열 조립하면 Windows 경로에서
  슬래시 개수가 안 맞아(`file://C:/...` vs 실제 `file:///C:/...`) 비교가 항상 거짓이 되고,
  **직접 실행해도 CLI 블록이 조용히 스킵되어 exit 0로 아무 일도 안 하고 끝난다** (실제로 겪음:
  출력도 결과 파일 갱신도 없이 성공한 것처럼 보였다). → `import { pathToFileURL } from 'url'`로
  변환해서 `import.meta.url === pathToFileURL(process.argv[1]).href`로 비교할 것.

* **tsx/esbuild의 `__name` 헬퍼 문제.** `page.evaluate`에 넘긴 함수 안에서
  `ReferenceError: __name is not defined`가 난다 (esbuild `keepNames`가 삽입하는 헬퍼가
  브라우저 컨텍스트에 없음). → `addInitScript`로 shim을 주입해 해결해 뒀다.

* **사이드바 Recents로 새 페이지를 찾으면 안 된다.** 사용 중 계속 바뀌어서
  전혀 무관한 기존 페이지를 집어온다. → 채팅 본문 영역(x>280) 링크가 1순위,
  사이드바는 "제목이 응답 텍스트에도 등장하는 링크"만 인정하는 폴백으로만 쓴다.

* **좌표(`x>280`)로 "채팅 본문 vs 사이드바"를 구분하는 건 불안정하다.** 사이드바 펼침
  상태 등에 따라 같은 링크도 실행마다 `inChat` 판정이 바뀌는 걸 실측으로 확인했다. 이것만
  믿고 아티팩트를 찾으면 사이드바의 무관한 페이지("My Tasks" 등)를 잘못 집어올 수 있다.
  → 근본 대책은 위 "아티팩트 탐색은 페이지 생성 신호가 있을 때만" 항목처럼 애초에 **탐색
  시도 자체를 게이팅**하는 것. 좌표/클래스 필터는 어디까지나 보조 방어선이다.

* **`notion-page-mention-token` 클래스가 붙은 링크는 아티팩트가 아니다.** AI가 인사말이나
  제안 문구에서 "이런 것도 도와드릴까요?" 식으로 **기존 페이지를 인라인 언급**할 때 이 클래스가
  붙는다. href가 beforeHrefs에 없다고 새 아티팩트로 오인하면 안 된다 — 이 멘션 토큰도 응답이
  렌더링될 때 새 DOM 노드로 생기므로 beforeHrefs diff로는 걸러지지 않는다. 실제로 "테스트" 같은
  잡담성 프롬프트에도 매번 "개인 MM 입력 - 2026년 7월" 페이지가 아티팩트로 오탐된 적이 있다.
  → `findArtifactLink`에서 `className`에 `notion-page-mention-token`이 있으면 후보에서 제외한다
  (2차 방어선. 1차 방어선은 위의 "페이지 생성 신호" 게이팅).

* **32자리 ID는 반드시 경로(pathname)에서 확인할 것.** 대화 스레드 링크는
  `/chat?t=<32hex>#main` 형태로 ID가 **쿼리**에 있다. `href` 전체에서 정규식을 돌리면
  접근성용 "Skip to content" 앵커를 아티팩트로 오탐한다.

* **응답 완료 판정에 길이 조건을 넣지 말 것.** `stable >= 3 && text.length > 200` 같은
  조건은 짧은 답변에서 영원히 거짓이 되어 타임아웃까지 헛돈다. "변화가 있었는가"로 판정한다.

* **아티팩트 페이지는 채팅이 완료된 뒤에도 계속 채워진다.** 한 번만 읽으면 앞부분만
  잘려 나온다(84자만 얻은 적 있음). → 내용 길이가 2회 연속 안 늘어날 때까지 재추출한다.

* **크롬 프로필**: `notion_chrome_profile` 재사용으로 로그인 세션 유지.
  최초 1회만 브라우저에서 직접 로그인하면 이후 자동 유지된다.

## 알려진 한계

* 인라인 서식(**굵게**, *기울임*, 링크)은 마크다운으로 복원되지 않는다 — 본문 텍스트만 보존.
* 코드블록의 언어 표기는 추출하지 않는다 (` ``` ` 펜스만).
