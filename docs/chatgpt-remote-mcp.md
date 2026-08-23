# ChatGPT 원격 PC MCP 연결

이 문서는 브라우저 ChatGPT에서 Windows PC의 로컬 프로젝트를 다루기 위한 1회성 설정 안내서다. 자동 실행 파일이나 에이전트 스킬이 아니다.

## 구성 요소

- 로컬 에이전트: `npx @wonderwhy-er/desktop-commander@latest remote`
- ChatGPT 플러그인: `AI Folder Remote`
- MCP 엔드포인트: `https://mcp.desktopcommander.app/mcp`
- 인증: OAuth 기기 인증

SSH와 포트 포워딩은 필요 없다. 로컬 에이전트가 실행 중일 때만 ChatGPT가 PC에 접근할 수 있다.

## 설정

1. ChatGPT에서 개발자 모드를 켠다.
2. 플러그인을 만들고 MCP 엔드포인트를 입력한 뒤 OAuth를 선택한다.
3. 로컬 에이전트를 실행한다.
4. 브라우저에 표시되는 기기 인증을 본인 계정으로 완료한다.
5. ChatGPT의 새 채팅에서 `AI Folder Remote`를 활성화한다.

## 사용

ChatGPT가 자체 `/workspace` 샌드박스를 사용하는 것을 막기 위해 원격 도구를 명시한다.

```text
AI Folder Remote(Desktop Commander)를 사용해서
C:\Users\<user>\Documents\ai 폴더를 확인해줘. ChatGPT 작업공간(/workspace)은 사용하지 마.
```

코드 수정, 빌드, 배포는 대상 파일과 실행 명령을 먼저 검토하고 승인한 뒤에 실행하도록 요청한다.

## 보안

Desktop Commander Remote는 제3자 서비스이며, 에이전트가 실행되는 동안 로컬 사용자 권한으로 동작할 수 있다. 사용하지 않을 때는 에이전트 창을 닫는다. 삭제, 배포, 패키지 게시, 비밀값 전송은 별도로 확인한다.
