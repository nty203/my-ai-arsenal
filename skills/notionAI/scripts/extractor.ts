import { chromium } from 'playwright';
import * as fs from 'fs';
import * as path from 'path';

const PROFILE_DIR = 'C:/Users/nam9n/.claude/skills/notionAI/notion_chrome_profile';
const DOWNLOAD_DIR = process.env.EXTRACT_DIR || 'C:/Users/nam9n/Downloads/notionAI';

async function main() {
  const targetUrl = process.argv[2] || '';
  if (!targetUrl) {
    console.error('사용법: npx tsx extractor.ts <notion-page-url>');
    process.exit(1);
  }

  fs.mkdirSync(DOWNLOAD_DIR, { recursive: true });

  console.log(`[Extractor] 브라우저 실행 중...`);
  const browser = await chromium.launchPersistentContext(PROFILE_DIR, {
    headless: false,
    viewport: { width: 1400, height: 900 },
    acceptDownloads: true,
  });

  try {
    const page = browser.pages()[0] || await browser.newPage();

    console.log(`[Extractor] 페이지 이동: ${targetUrl}`);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded' });

    console.log('[Extractor] 15초 대기 (아티팩트 렌더링)...');
    await page.waitForTimeout(15000);

    // .html 파일 블록 클릭 → 인라인 뷰어 모달
    const htmlBlockLoc = page.locator('div, span').filter({ hasText: '.html' }).last();
    const count = await htmlBlockLoc.count();

    if (count > 0) {
      console.log(`[Extractor] .html 파일 블록 발견. 클릭...`);
      await htmlBlockLoc.click({ force: true }).catch(() => {});
      await page.waitForTimeout(6000);
    } else {
      console.log('[Extractor] .html 블록 없음. 다운로드 버튼 직접 탐색...');
    }

    const downloadPromise = page.waitForEvent('download', { timeout: 15000 }).catch(() => null);

    const found = await page.evaluate(`(async () => {
      const sleep = (ms) => new Promise(r => setTimeout(r, ms));

      // 바깥에 노출된 Download 버튼 먼저 확인
      const outerMenus = Array.from(document.querySelectorAll('div[role="button"]'));
      const directDl = outerMenus.find(m => {
        const lbl = m.getAttribute('aria-label') || '';
        const txt = m.textContent || '';
        return lbl.includes('Download') || lbl.includes('Export') || txt.includes('Download');
      });
      if (directDl) { directDl.click(); return true; }

      // 상단 버튼들 순차 클릭해서 드롭다운 탐색
      const btns = Array.from(document.querySelectorAll('div[role="button"]'));
      for (let i = btns.length - 1; i >= Math.max(0, btns.length - 50); i--) {
        btns[i].click();
        await sleep(350);
        const menus = Array.from(document.querySelectorAll('div[role="menuitem"], a[download], div.notion-dropdown-menu'));
        const dlMenu = menus.find(m => {
          const text = (m.textContent || '').toLowerCase();
          return text.includes('download') || text.includes('export');
        });
        if (dlMenu) { dlMenu.click(); return true; }
        document.body.click();
        await sleep(150);
      }
      return false;
    })()`);

    if (found) {
      console.log('[Extractor] 다운로드 메뉴 발견!');
      const download = await downloadPromise;
      if (download) {
        const savePath = path.join(DOWNLOAD_DIR, download.suggestedFilename());
        await download.saveAs(savePath);
        console.log(`\n✅ 다운로드 완료: ${savePath}\n`);
      }
    } else {
      console.log('[Extractor] 다운로드 메뉴를 찾지 못함. 페이지 텍스트 덤프...');
      const body = await page.evaluate(() => document.body.innerText);
      const dumpPath = path.join(DOWNLOAD_DIR, 'debug_body.txt');
      fs.writeFileSync(dumpPath, body, 'utf8');
      console.log(`덤프 저장: ${dumpPath}`);
    }

  } catch (error) {
    console.error('[Extractor] 오류:', error);
  } finally {
    await browser.close();
  }
}

main();
