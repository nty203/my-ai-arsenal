import { chromium, Route, Request } from 'playwright';
import path from 'path';
import fs from 'fs';

export interface NotionAiOptions {
  profileDir?: string;
  headless?: boolean;
  targetPageUrl?: string;
  model?: string;
}

export async function askNotionAi(prompt: string, options: NotionAiOptions = {}): Promise<string> {
  const globalProfileDir = 'C:/Users/tzero/Documents/ai/notion_chrome_profile';
  const profileDir = options.profileDir || globalProfileDir;
  const headless = options.headless ?? false;
  const targetModel = options.model || 'Fable 5';

  const browser = await chromium.launchPersistentContext(profileDir, {
    headless,
    viewport: { width: 1280, height: 900 },
  });

  let page = browser.pages()[0] || await browser.newPage();
  let capturedResponse = '';
  let responseFinished = false;

  try {
    // 1. Notion AI 채팅 페이지로 이동
    console.log('Notion AI 채팅 페이지로 이동 중...');
    await page.goto('https://app.notion.com/ai', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(3000);

    // 2. 로그인 확인
    const isLoggedIn = await page.evaluate(() =>
      !!document.querySelector('nav, [data-testid="sidebar"], [class*="sidebar"]')
    ).catch(() => false);

    if (!isLoggedIn) {
      console.log('로그인이 필요합니다. 로그인 후 자동으로 진행합니다...');
      await page.goto('https://www.notion.so/login', { waitUntil: 'domcontentloaded' });
      const loginStart = Date.now();
      while (Date.now() - loginStart < 300000) {
        if (page.isClosed()) break;
        const loggedIn = await page.evaluate(() =>
          !!document.querySelector('nav, [class*="sidebar"]')
        ).catch(() => false);
        if (loggedIn) {
          console.log('로그인 확인 완료!');
          await page.goto('https://app.notion.com/ai', { waitUntil: 'domcontentloaded' });
          await page.waitForTimeout(3000);
          break;
        }
        await page.waitForTimeout(2000);
      }
    } else {
      console.log('로그인 상태 확인 완료!');
    }

    // 3. 네트워크 응답 인터셉터 설정 (AI 스트리밍 응답 직접 캡처)
    console.log('네트워크 응답 인터셉터 설정 중...');
    
    // Notion AI 응답 스트림 인터셉트
    browser.on('response', async (response) => {
      const url = response.url();
      // Notion AI 스트리밍 엔드포인트 탐지
      if (url.includes('notion.com') && (
        url.includes('/api/v3/runInferenceStream') ||
        url.includes('/api/v3/transact') ||
        url.includes('inference') ||
        url.includes('ai/') ||
        url.includes('stream')
      )) {
        try {
          const text = await response.text().catch(() => '');
          if (text && text.length > 50) {
            console.log(`[인터셉트] AI 응답 감지 (${text.length}자): ${url.substring(0, 80)}`);
            // SSE 스트림에서 실제 텍스트 파싱
            const lines = text.split('\n');
            const extracted: string[] = [];
            for (const line of lines) {
              if (line.startsWith('data: ')) {
                try {
                  const data = JSON.parse(line.slice(6));
                  if (data.content) extracted.push(data.content);
                  else if (data.text) extracted.push(data.text);
                  else if (data.delta?.text) extracted.push(data.delta.text);
                  else if (typeof data === 'string') extracted.push(data);
                } catch {
                  // JSON이 아니면 그냥 추가
                  const raw = line.slice(6).trim();
                  if (raw && raw !== '[DONE]') extracted.push(raw);
                }
              }
            }
            if (extracted.length > 0) {
              capturedResponse += extracted.join('');
              console.log(`[인터셉트] 텍스트 파싱 완료: ${capturedResponse.length}자`);
            } else {
              // 파싱 실패 시 원본 텍스트 저장 (후처리)
              capturedResponse += text;
            }
          }
        } catch { /* 무시 */ }
      }
    });

    // 4. 모델 선택 (Fable 5)
    console.log(`모델 [${targetModel}] 선택 중...`);
    const modelClicked = await page.evaluate(() => {
      const btn = document.querySelector('[data-testid="unified-chat-model-button"]') as HTMLElement;
      if (btn) { btn.click(); return true; }
      return false;
    });

    if (modelClicked) {
      await page.waitForTimeout(1000);
      const modelSelected = await page.evaluate((model) => {
        const items = document.querySelectorAll('[role="menuitem"]');
        const target = Array.from(items).find(el => el.textContent?.trim() === model);
        if (target) { (target as HTMLElement).click(); return true; }
        return false;
      }, targetModel);

      if (modelSelected === true) {
        console.log(`모델 [${targetModel}] 선택 완료!`);
      } else {
        console.log(`모델 목록에서 ${targetModel}을 찾지 못했습니다. Auto로 진행합니다.`);
      }
      await page.waitForTimeout(1000);
    }

    // 5. 입력창에 프롬프트 삽입
    console.log('AI 입력창에 프롬프트 삽입 중...');
    await page.waitForSelector('div[contenteditable="true"], textarea', { timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(500);

    await page.evaluate((text) => {
      const el = document.querySelector('div[contenteditable="true"], textarea') as HTMLElement;
      if (el) {
        el.focus();
        document.execCommand('insertText', false, text);
      }
    }, prompt);
    await page.waitForTimeout(1000);

    // 6. 전송
    console.log('AI에게 프롬프트 전송 중...');
    await page.keyboard.press('Enter');

    // 7. AI 응답 완료까지 대기 (최대 3분)
    // 인터셉터 방식: 네트워크 응답이 충분히 클 때까지 대기
    console.log(`Fable 5 응답 스트리밍 대기 중 (최대 3분)...`);
    const start = Date.now();
    let lastCapturedLen = 0;
    let stableCount = 0;

    // DOM 기반 백업 수집도 병행 실행
    while (Date.now() - start < 180000) {
      await page.waitForTimeout(3000).catch(() => {});

      // 인터셉터로 충분한 응답이 캡처된 경우
      if (capturedResponse.length > lastCapturedLen) {
        lastCapturedLen = capturedResponse.length;
        stableCount = 0;
        console.log(`인터셉터 수집 중... (${capturedResponse.length}자)`);
        continue;
      }

      // DOM 기반 백업 수집
      if (!page.isClosed()) {
        try {
          const domState = await page.evaluate(() => {
            let bodyText = document.body.innerText;
            // 노션의 모든 텍스트 블록(아티팩트) 추출
            const blocks = document.querySelectorAll('[data-block-id]');
            if (blocks.length > 0) {
              bodyText += '\n\n=== [Artifact Content] ===\n';
              blocks.forEach(block => {
                bodyText += block.textContent + '\n';
              });
            }
            const isGenerating = bodyText.includes('Generating') || bodyText.includes('Stop generating') || bodyText.includes('Thinking') || bodyText.includes('Creating page') || bodyText.includes('Vibing');
            return { isGenerating, length: bodyText.length, text: bodyText };
          }).catch(() => null);

          if (domState) {
            if (domState.isGenerating) {
              console.log(`Fable 5 생성 중... DOM: ${domState.length}자`);
              stableCount = 0;
              continue;
            }
            if (domState.length > lastCapturedLen) {
              lastCapturedLen = domState.length;
              if (!capturedResponse || capturedResponse.length < domState.length) {
                capturedResponse = domState.text;
              }
              stableCount = 0;
              console.log(`DOM 수집 중... (${domState.length}자)`);
              continue;
            }
          }
        } catch { /* 무시 */ }
      }

      // 응답이 안정화됨
      if (lastCapturedLen > 500) {
        stableCount++;
        console.log(`응답 안정화 체크 ${stableCount}/3...`);
        if (stableCount >= 3) {
          console.log('응답 안정화 확인, 수집 완료!');
          responseFinished = true;
          break;
        }
      }
    }

    // 8. 노션 AI가 작성한 새 아티팩트 페이지 링크(Open page)를 찾아 클릭 후 찐 원본 추출
    try {
      if (!page.isClosed()) {
        console.log('[Artifact Extraction] Looking for "Open page" link...');
        const openPageBtns = await page.$$('div:has-text("Open page")');
        let clicked = false;
        for (let i = openPageBtns.length - 1; i >= 0; i--) {
            const text = await openPageBtns[i].innerText();
            if (text.includes('Open page')) {
                console.log('[Artifact Extraction] Clicking "Open page"...');
                await openPageBtns[i].click({ force: true }).catch(() => {});
                clicked = true;
                break;
            }
        }

        if (clicked) {
            console.log('[Artifact Extraction] Waiting for artifact page to load...');
            await page.waitForTimeout(8000); // 렌더링 대기
            
            const trueContent = await page.evaluate(() => {
                const main = document.querySelector('.notion-page-content') || document.querySelector('main');
                return main ? main.innerText : '';
            });

            if (trueContent.trim()) {
                console.log(`[Artifact Extraction] Success! Extracted ${trueContent.length} chars from new page.`);
                capturedResponse = '\n\n=== [True Artifact Content] ===\n\n' + trueContent;
            }
        }
      }
    } catch (e) {
      console.log('[Artifact Extraction] Error during extraction:', e);
    }

    // 9. 스크린샷 저장
    try {
      if (!page.isClosed()) {
        await page.screenshot({ path: 'last_response.png' });
        console.log('스크린샷 저장: last_response.png');
      }
    } catch { /* 무시 */ }

    console.log(`최종 수집된 응답: ${capturedResponse.length}자`);
    return capturedResponse;

  } finally {
    await browser.close().catch(() => {});
  }
}
