/**
 * Notion AI에서 현재 선택 가능한 모델 목록을 가져온다 (프롬프트 전송 없이 조회만).
 *
 *   npx tsx listModels.ts            # JSON 배열로 출력
 *
 * Notion 쪽 모델 라인업(GPT 계열/Claude 계열 등)이 수시로 바뀌므로, 매번 실제
 * 드롭다운을 열어 실측한 뒤 그 결과를 사용자에게 보여주고 고르게 하기 위한 스크립트다.
 * executor.ts처럼 파일 하단에 즉시 실행 로직을 안 넣으면 import가 곤란하므로
 * 여기서도 바로 실행 스크립트로 둔다 (다른 곳에서 재사용할 필요 없음).
 */
import { chromium } from 'playwright';
import { ensureLoggedIn } from './session.js';
import { SEL, listAvailableModels } from './notionUi.js';

const PROFILE_DIR = 'C:/Users/nam9n/.claude/skills/notionAI/notion_chrome_profile';

async function main() {
  const headless = process.argv.includes('--headless');

  const browser = await chromium.launchPersistentContext(PROFILE_DIR, {
    headless,
    viewport: { width: 1280, height: 900 },
  });
  const page = browser.pages()[0] || await browser.newPage();
  await page.addInitScript({ content: 'globalThis.__name = globalThis.__name || ((f) => f);' });
  await page.evaluate('globalThis.__name = globalThis.__name || ((f) => f)').catch(() => {});

  try {
    await ensureLoggedIn(page, { headless });
    await page.waitForSelector(SEL.modelButton, { timeout: 20000 });

    const models = await listAvailableModels(page);
    if (models.length === 0) throw new Error('모델 메뉴에서 항목을 하나도 찾지 못했습니다.');

    console.log(JSON.stringify(models));
  } finally {
    await browser.close().catch(() => {});
  }
}

main().catch(err => {
  console.error('❌ 모델 목록 조회 실패:', err.message);
  process.exit(1);
});
