/**
 * Notion 로그인 세션 만들기 (최초 1회).
 *
 *   npx tsx login.ts
 *
 * 브라우저가 뜨면 직접 로그인하면 된다. 로그인 정보는 이 스크립트를 거치지 않고
 * 크롬 프로필(notion_chrome_profile)에 저장되며, 이후 executor/fetchPage가 그대로 재사용한다.
 */
import { chromium } from 'playwright';
import { ensureLoggedIn } from './session.js';

const PROFILE_DIR = 'C:/Users/nam9n/.claude/skills/notionAI/notion_chrome_profile';

async function main() {
  const browser = await chromium.launchPersistentContext(PROFILE_DIR, {
    headless: false,
    viewport: { width: 1280, height: 900 },
  });
  const page = browser.pages()[0] || await browser.newPage();
  await page.addInitScript({ content: 'globalThis.__name = globalThis.__name || ((f) => f);' });

  try {
    await ensureLoggedIn(page, { headless: false, loginTimeoutMs: 600000 });
    console.log('\n이제 executor.ts / fetchPage.ts 를 바로 쓸 수 있습니다.');
  } finally {
    await browser.close().catch(() => {});
  }
}

main().catch(err => {
  console.error('\n❌', err.message);
  process.exit(1);
});
