/**
 * Notion 페이지를 URL로 직접 가져와 마크다운으로 저장한다 (MCP 불필요).
 *
 *   npx tsx fetchPage.ts <노션페이지URL> [출력파일경로]
 *
 * executor.ts가 이미 저장한 last_artifact.json의 url을 넣어 재추출할 수도 있다.
 */
import { chromium } from 'playwright';
import fs from 'fs';
import { extractNotionPage } from './pageExtract.js';

const PROFILE_DIR = 'C:/Users/nam9n/.claude/skills/notionAI/notion_chrome_profile';

async function main() {
  const url = process.argv[2];
  const outPath = process.argv[3] || 'last_page.md';

  if (!url) {
    console.error('사용법: npx tsx fetchPage.ts <노션페이지URL> [출력파일경로]');
    process.exit(1);
  }

  const browser = await chromium.launchPersistentContext(PROFILE_DIR, {
    headless: true,
    viewport: { width: 1400, height: 950 },
  });
  const page = browser.pages()[0] || await browser.newPage();
  await page.addInitScript({ content: 'globalThis.__name = globalThis.__name || ((f) => f);' });

  try {
    console.log(`추출 중: ${url}`);
    const r = await extractNotionPage(page, url);

    if (!r.ok || !r.markdown) {
      console.error(`❌ 추출 실패: ${r.reason || '본문 없음'}`);
      console.error('   로그인 세션이 유효한지, URL이 접근 가능한 페이지인지 확인하세요.');
      process.exit(1);
    }

    fs.writeFileSync(outPath, `# ${r.title}\n\n> 출처: ${r.url}\n\n${r.markdown}\n`, 'utf8');
    console.log(`✅ "${r.title}" — ${r.blockCount}블록 → 마크다운 ${r.markdown.length}자`);
    console.log(`   저장: ${outPath}`);
  } finally {
    await browser.close().catch(() => {});
  }
}

main().catch(err => {
  console.error('❌ 오류:', err.message);
  process.exit(1);
});
