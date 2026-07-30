import { chromium } from 'playwright';
import * as fs from 'fs';
import * as path from 'path';

async function main() {
  const profileDir = 'C:/Users/tzero/Documents/ai/notion_chrome_profile';
  console.log(`[Universal Extractor Final] Launching browser...`);

  const browser = await chromium.launchPersistentContext(profileDir, {
    headless: false,
    viewport: { width: 1400, height: 900 },
    acceptDownloads: true
  });

  try {
    const page = browser.pages()[0] || await browser.newPage();
    const targetUrl = 'https://app.notion.com/chat?t=3a8dadb56b2f80ae84d900a961de2529&wfv=chat';
    
    console.log(`[Universal Extractor Final] Navigating to URL...`);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded' });
    
    console.log('[Universal Extractor Final] Waiting 15s for page and artifacts to render...');
    await page.waitForTimeout(15000);

    // 1. 파일 블록 클릭 (인라인 뷰어 모달 띄우기)
    console.log('[Universal Extractor Final] Looking for file block (.html)...');
    const htmlBlockLoc = page.locator('div, span').filter({ hasText: '.html' }).last();
    const count = await htmlBlockLoc.count();
    
    if (count > 0) {
        console.log(`[Universal Extractor Final] Found .html file block. Clicking to open Inline Viewer modal...`);
        await htmlBlockLoc.click({ force: true }).catch(() => {});
        console.log('[Universal Extractor Final] Waiting 6s for Inline Viewer to load...');
        await page.waitForTimeout(6000);
    } else {
        console.log('[Universal Extractor Final] .html block not found!');
    }

    let downloaded = false;

    // 2. 다운로드 리스너 준비
    const downloadPromise = page.waitForEvent('download', { timeout: 15000 }).catch(() => null);

    // Playwright Locator 충돌(Stale) 및 TS 트랜스파일(에러)을 피하기 위해 String 형태로 삽입
    console.log('[Universal Extractor Final] Executing string-based JS brute-force click on Header Buttons (More -> Download)...');
    
    const found = await page.evaluate(`(async () => {
        const sleep = (ms) => new Promise(r => setTimeout(r, ms));
        
        // 1. 혹시 밖에 바로 튀어나와있는 Download 버튼이 있는지 먼저 확인
        const outerMenus = Array.from(document.querySelectorAll('div[role="button"]'));
        const directDl = outerMenus.find(m => {
             const lbl = m.getAttribute('aria-label') || '';
             const txt = m.textContent || '';
             return lbl.includes('Download') || lbl.includes('Export') || txt.includes('Download');
        });
        
        if (directDl) {
             directDl.click();
             return true;
        }

        // 2. 밖에서 안 보인다면 상단에 있는 모든 버튼을 누르며 드롭다운 메뉴 열기
        const btns = Array.from(document.querySelectorAll('div[role="button"]'));
        // 상단에 위치한 버튼들(주로 DOM 맨 뒤쪽에 렌더링됨) 50개를 순차적으로 클릭
        for (let i = btns.length - 1; i >= Math.max(0, btns.length - 50); i--) {
            btns[i].click();
            await sleep(350); // 메뉴 렌더링 대기
            
            const menus = Array.from(document.querySelectorAll('div[role="menuitem"], a[download], div.notion-dropdown-menu'));
            const dlMenu = menus.find(m => {
                const text = (m.textContent || '').toLowerCase();
                return text.includes('download') || text.includes('export');
            });
            
            if (dlMenu) {
                dlMenu.click();
                return true;
            }
            
            // 메뉴가 없었다면 바디 클릭해서 드롭다운 닫기
            document.body.click();
            await sleep(150);
        }
        return false;
    })()`);

    if (found) {
         console.log(`[Universal Extractor Final] Jackpot! Triggered Download menu!`);
         
         const download = await downloadPromise;
         if (download) {
             const downloadPath = path.join('C:\\Users\\tzero\\Documents\\ai\\myRag\\docs\\raw', download.suggestedFilename());
             await download.saveAs(downloadPath);
             console.log(`\n=============================================`);
             console.log(`[Universal Extractor Final] SUCCESS! File legally downloaded via Notion UI!`);
             console.log(`[Universal Extractor Final] Saved to: ${downloadPath}`);
             console.log(`=============================================\n`);
             downloaded = true;
         }
    } else {
         console.log(`[Universal Extractor Final] JavaScript clicker could not find the Download menu.`);
    }

    if (!downloaded) {
         console.log('[Universal Extractor Final] Download event did not fire. Dumping body for inspection...');
         const body = await page.evaluate(() => document.body.innerText);
         fs.writeFileSync('C:\\Users\\tzero\\Documents\\ai\\myRag\\docs\\raw\\debug_body_final.txt', body, 'utf8');
    }

  } catch (error) {
    console.error('Error during extraction:', error);
  } finally {
    await browser.close();
  }
}

main();
