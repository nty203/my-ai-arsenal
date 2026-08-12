/**
 * Notion 로그인 세션 보장.
 *
 * 로그인은 영속 크롬 프로필(notion_chrome_profile)에 저장되므로 최초 1회만 하면 된다.
 * 다만 세션 만료/프로필 삭제 시 다시 필요하므로, "로그인이 안 된 상태"를
 * 명확히 감지해서 사람이 알아들을 수 있는 안내를 내보내는 것이 이 모듈의 목적이다.
 *
 * 기존 구현의 문제:
 *  - 판정 셀렉터가 `nav, [class*="sidebar"]`로 너무 느슨해 로그인 페이지에서도 참이 될 수 있었다.
 *    (오탐하면 로그인을 건너뛰고 한참 뒤 엉뚱한 곳에서 타임아웃 에러가 난다)
 *  - headless 모드에서는 사람이 로그인할 방법이 없는데도 5분을 기다렸다.
 *  - 타임아웃 시 아무 안내 없이 죽었다.
 */

const LOGIN_HINT = `
로그인 세션이 없습니다. 아래 명령으로 브라우저를 띄워 한 번만 로그인하세요.
로그인 정보는 이 스크립트가 아니라 크롬 프로필에 저장되며, 이후 자동 유지됩니다.

  cd "C:/Users/nam9n/.claude/skills/notionAI/scripts" && npx tsx login.ts
`;

/** 로그인 완료 신호: AI 채팅 UI가 떠 있어야 한다 (로그인 페이지에는 절대 없는 요소) */
const LOGGED_IN_PROBE = `(() => {
  return !!document.querySelector(
    '[data-testid="unified-chat-model-button"], [data-testid="agent-send-message-button"]'
  );
})()`;

/** 로그아웃 신호: 로그인 폼이나 /login URL */
const LOGGED_OUT_PROBE = `(() => {
  if (/\\/login|\\/signup/.test(location.pathname)) return true;
  return !!document.querySelector('input[type="email"], input[name="email"]');
})()`;

export interface EnsureLoginOptions {
  /** headless면 사람이 로그인할 수 없으므로 즉시 실패시킨다 */
  headless?: boolean;
  /** 사람이 로그인하기를 기다리는 시간 (기본 5분) */
  loginTimeoutMs?: number;
}

/**
 * Notion AI 화면까지 진입해 로그인 상태를 보장한다.
 * 로그인이 안 되어 있고 headless면 예외를 던진다 (조용히 매달리지 않는다).
 */
export async function ensureLoggedIn(page: any, options: EnsureLoginOptions = {}): Promise<void> {
  const headless = options.headless ?? false;
  const loginTimeoutMs = options.loginTimeoutMs ?? 300000;

  await page.goto('https://app.notion.com/ai', { waitUntil: 'domcontentloaded' });

  // 앱 셸이 뜰 때까지 최대 25초 — 로그인/미로그인 어느 쪽이든 신호가 잡힐 때까지
  for (let i = 0; i < 25; i++) {
    if (await page.evaluate(LOGGED_IN_PROBE).catch(() => false)) {
      console.log('로그인 상태 확인됨.');
      return;
    }
    if (await page.evaluate(LOGGED_OUT_PROBE).catch(() => false)) break;
    await page.waitForTimeout(1000);
  }

  // 여기까지 왔으면 로그인 안 된 것으로 본다
  if (headless) {
    throw new Error(`headless 모드에서는 로그인할 수 없습니다.${LOGIN_HINT}`);
  }

  console.log(`로그인이 필요합니다. 열린 브라우저에서 로그인하세요 (최대 ${Math.round(loginTimeoutMs / 60000)}분 대기)...`);
  await page.goto('https://www.notion.so/login', { waitUntil: 'domcontentloaded' });

  const start = Date.now();
  while (Date.now() - start < loginTimeoutMs) {
    if (page.isClosed()) {
      throw new Error('로그인 도중 브라우저가 닫혔습니다.');
    }
    // 로그인에 성공하면 앱으로 리다이렉트된다 — /ai로 이동해 채팅 UI가 뜨는지 확인
    const onLogin = await page.evaluate(LOGGED_OUT_PROBE).catch(() => true);
    if (!onLogin) {
      await page.goto('https://app.notion.com/ai', { waitUntil: 'domcontentloaded' }).catch(() => {});
      for (let i = 0; i < 20; i++) {
        if (await page.evaluate(LOGGED_IN_PROBE).catch(() => false)) {
          console.log('✅ 로그인 완료 — 세션이 크롬 프로필에 저장되었습니다.');
          return;
        }
        await page.waitForTimeout(1000);
      }
    }
    await page.waitForTimeout(2000);
  }

  throw new Error(`로그인 대기 시간이 초과되었습니다.${LOGIN_HINT}`);
}

/**
 * 페이지 추출처럼 "이미 로그인돼 있어야 하는" 작업에서 세션만 확인한다.
 * 로그인 폼이 뜨면 즉시 명확한 예외를 던진다.
 */
export async function assertLoggedIn(page: any): Promise<void> {
  const loggedOut = await page.evaluate(LOGGED_OUT_PROBE).catch(() => false);
  if (loggedOut) {
    throw new Error(`Notion 로그인이 필요합니다 (로그인 페이지로 리다이렉트됨).${LOGIN_HINT}`);
  }
}
