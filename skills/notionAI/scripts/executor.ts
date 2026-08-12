import { chromium } from 'playwright';
import path from 'path';
import fs from 'fs';
import { pathToFileURL } from 'url';
import { extractNotionPage, findArtifactLink } from './pageExtract.js';
import { ensureLoggedIn } from './session.js';
import { SEL, clickBySelector, selectModel } from './notionUi.js';

const PROFILE_DIR = 'C:/Users/nam9n/.claude/skills/notionAI/notion_chrome_profile';

export interface NotionAiOptions {
  profileDir?: string;
  headless?: boolean;
  model?: string;
  imagePath?: string;
  timeoutMs?: number;
}

export interface NotionAiResult {
  /** 채팅 화면에서 읽은 응답 텍스트 */
  chatText: string;
  /** AI가 아티팩트 페이지를 만들었다면 그 URL */
  pageUrl?: string;
  pageTitle?: string;
  /** 아티팩트 페이지 본문을 마크다운으로 변환한 것 */
  markdown?: string;
}

/** 사이드바를 제외한 채팅 본문 영역의 텍스트만 추출 (사이드바 Recents 변화에 오염되지 않도록) */
const CHAT_TEXT_FN = `() => {
  const cands = Array.from(document.querySelectorAll('div')).filter(d => {
    const r = d.getBoundingClientRect();
    return r.x > 280 && r.width > 400 && r.height > 300;
  });
  let best = '';
  for (const c of cands) {
    const t = c.innerText || '';
    if (t.length > best.length) best = t;
  }
  return best || document.body.innerText;
}`;

async function pasteImage(page: any, context: any, imagePath: string): Promise<boolean> {
  if (!fs.existsSync(imagePath)) {
    console.warn(`이미지 파일 없음: ${imagePath}`);
    return false;
  }
  const imageBuffer = fs.readFileSync(imagePath);
  const ext = path.extname(imagePath).toLowerCase();
  const mimeType = ext === '.jpg' || ext === '.jpeg' ? 'image/jpeg'
    : ext === '.gif' ? 'image/gif'
    : ext === '.webp' ? 'image/webp'
    : 'image/png';
  const base64 = imageBuffer.toString('base64');
  const filename = path.basename(imagePath);

  console.log(`이미지 붙여넣기: ${filename} (${Math.round(imageBuffer.length / 1024)}KB)`);
  await context.grantPermissions(['clipboard-read', 'clipboard-write'], {
    origin: 'https://app.notion.com',
  }).catch(() => {});

  const editor = await page.$(SEL.editor);
  if (editor) await editor.click().catch(() => {});
  await page.waitForTimeout(300);

  const ok = await page.evaluate(
    async ({ base64, mimeType, filename }: any) => {
      try {
        const blob = await fetch(`data:${mimeType};base64,${base64}`).then(r => r.blob());
        try {
          await navigator.clipboard.write([new ClipboardItem({ [mimeType]: blob })]);
          return 'clipboard';
        } catch { /* fallthrough */ }
        const file = new File([blob], filename, { type: mimeType });
        const dt = new DataTransfer();
        dt.items.add(file);
        const el = document.querySelector('div[contenteditable="true"]') as HTMLElement;
        if (!el) return '';
        el.focus();
        el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
        return 'event';
      } catch { return ''; }
    },
    { base64, mimeType, filename }
  );

  if (ok === 'clipboard') await page.keyboard.press('Control+v');
  if (!ok) { console.warn('이미지 붙여넣기 실패'); return false; }
  await page.waitForTimeout(4000);
  return true;
}

/**
 * 이미 로그인·모델버튼까지 뜬 page에 대해 "모델 선택 → 프롬프트 전송 → 응답 대기 →
 * 아티팩트 추출"을 수행한다. 브라우저를 열고 닫는 건 호출자 책임이다 — interactive.ts처럼
 * 모델 목록 조회 후 사용자 선택을 기다리는 동안 브라우저를 계속 띄워둬야 하는 경우
 * askNotionAi(브라우저를 직접 열고 닫음)를 쓸 수 없어서 분리했다.
 */
export async function runPrompt(
  page: any,
  browser: any,
  prompt: string,
  options: { model?: string; imagePath?: string; timeoutMs?: number } = {}
): Promise<NotionAiResult> {
  const targetModel = options.model || 'Fable 5';
  const imagePath = options.imagePath || '';
  const timeoutMs = options.timeoutMs ?? 300000;

  {
    // ── 모델 선택 (실패 시 예외) ───────────────────────────────
    await selectModel(page, targetModel);

    // ── 입력 ──────────────────────────────────────────────────
    await page.waitForSelector(SEL.editor, { timeout: 15000 });
    await clickBySelector(page, 'div[contenteditable="true"]');
    await page.waitForTimeout(300);

    // 영속 프로필이라 이전 실행의 초안 텍스트가 입력창에 남아있을 수 있다.
    // 그대로 두면 프롬프트가 오염되므로 반드시 비운다.
    const leftover = await page.evaluate('(() => { var el = document.querySelector(\'div[contenteditable="true"], textarea\'); return (el && (el.textContent || el.value) || "").trim().length; })()') as number;
    if (leftover > 0) {
      console.log(`입력창에 남은 초안 ${leftover}자 → 삭제`);
      await page.keyboard.press('Control+a');
      await page.keyboard.press('Backspace');
      await page.waitForTimeout(500);
    }

    if (imagePath) await pasteImage(page, browser, imagePath);

    console.log('프롬프트 입력 중...');
    await page.evaluate((text: string) => {
      const el = document.querySelector('div[contenteditable="true"], textarea') as HTMLElement;
      el.focus();
      document.execCommand('insertText', false, text);
      el.dispatchEvent(new InputEvent('input', { bubbles: true }));
    }, prompt);
    await page.waitForTimeout(1200);

    const inputLen = await page.evaluate(() => {
      const el = document.querySelector('div[contenteditable="true"], textarea') as any;
      return (el?.textContent || el?.value || '').length;
    });
    const expectedLen = prompt.trim().length;
    if (inputLen < expectedLen) throw new Error(`프롬프트 입력 실패 (입력창 ${inputLen}자, 기대 ${expectedLen}자)`);
    console.log(`입력 완료: ${inputLen}자`);

    // 전송 직전 링크 스냅샷 — 나중에 "새로 생긴 페이지"를 가려내는 기준
    const beforeHrefs = await page.evaluate(
      'Array.prototype.slice.call(document.querySelectorAll("a[href]")).map(function(a){ return a.href; })'
    ).catch(() => []) as string[];

    // ── 전송 ──────────────────────────────────────────────────
    const sent = await clickBySelector(page, SEL.sendButton);
    if (!sent) {
      console.log('전송 버튼 못 찾음 → Enter 폴백');
      await page.keyboard.press('Enter');
    }
    await page.waitForTimeout(2500);

    const afterLen = await page.evaluate(() => {
      const el = document.querySelector('div[contenteditable="true"], textarea') as any;
      return (el?.textContent || el?.value || '').length;
    });
    if (afterLen >= inputLen) {
      console.warn(`⚠️ 입력창이 비워지지 않음 (${afterLen}자) — 전송 실패 가능성`);
    } else {
      console.log('전송 확인됨.');
    }

    // ── 응답 대기 ─────────────────────────────────────────────
    console.log(`응답 대기 중 (최대 ${Math.round(timeoutMs / 60000)}분)...`);
    const start = Date.now();
    let lastText = '';
    let stable = 0;
    // 응답이 짧아도 끝낼 수 있어야 한다. 길이로 판정하면(예: >200자) 짧은 답변에서
    // 종료 조건이 영원히 거짓이 되어 타임아웃까지 헛돈다 — 실제로 겪은 버그.
    let sawActivity = false;
    // "Creating page…"/"Vibing…" 은 AI가 실제로 페이지(아티팩트)를 만드는 중일 때만
    // 뜨는 문구다 (일반 잡담에서는 "Thinking…"/"Generating…"만 뜬다). 좌표나 클래스명
    // 기반 DOM 휴리스틱은 사이드바 펼침 상태 등에 따라 실행마다 흔들리는 걸 실측으로
    // 확인했다 — 이 신호는 훨씬 신뢰도가 높으므로, 이걸 본 적이 없으면 아예 아티팩트
    // 탐색을 시도하지 않는다 (오탐의 근본 원인 차단).
    let sawArtifactSignal = false;

    while (Date.now() - start < timeoutMs) {
      await page.waitForTimeout(3000);
      // 생성 중 판정: 텍스트 휴리스틱보다 "중지" 버튼 존재 여부가 훨씬 신뢰도 높다.
      const state = await page.evaluate(`(() => {
        var cands = Array.prototype.slice.call(document.querySelectorAll('div')).filter(function (d) {
          var r = d.getBoundingClientRect();
          return r.x > 280 && r.width > 400 && r.height > 300;
        });
        var best = '';
        for (var i = 0; i < cands.length; i++) {
          var t = cands[i].innerText || '';
          if (t.length > best.length) best = t;
        }
        if (!best) best = document.body.innerText;
        var stopBtn = document.querySelector('[aria-label*="Stop" i], [data-testid*="stop" i]');
        // 주의: "Found N results" 같은 문구는 완료 후에도 대화록에 남으므로 판정에 쓰면 안 된다.
        var generating = !!stopBtn || /Stop generating|Generating…|Thinking…|Creating page|Vibing/i.test(best);
        var creatingPage = /Creating page|Vibing/i.test(best);
        return { text: best, generating: generating, creatingPage: creatingPage };
      })()`).catch(() => null);
      if (!state) continue;

      if (state.creatingPage) sawArtifactSignal = true;

      if (state.generating) {
        console.log(`생성 중... (${state.text.length}자)`);
        lastText = state.text;
        stable = 0;
        sawActivity = true;
        continue;
      }
      if (state.text !== lastText) {
        console.log(`변화 감지 (${state.text.length}자)`);
        lastText = state.text;
        stable = 0;
        sawActivity = true;
        continue;
      }
      stable++;
      console.log(`안정화 ${stable}/3`);
      if (stable >= 3 && sawActivity && lastText.length > 0) break;
    }

    await page.screenshot({ path: 'last_response.png', fullPage: true }).catch(() => {});
    console.log(`채팅 응답 수집: ${lastText.length}자`);

    // ── 아티팩트 페이지 추출 (MCP 없이 브라우저에서 직접) ──────
    const result: NotionAiResult = { chatText: lastText };
    if (!sawArtifactSignal) {
      // 생성 과정에서 "페이지를 만드는 중" 신호를 한 번도 못 봤다 — 잡담성 응답이다.
      // 이 경우 링크 탐색 자체를 하지 않는다: 사이드바/멘션 오탐의 근본 원인이었다.
      console.log('페이지 생성 신호 없음 — 아티팩트 탐색 생략, 텍스트 응답으로 처리');
    } else {
      try {
        const link = await findArtifactLink(page, beforeHrefs, lastText);
        if (link) {
          console.log(`아티팩트 페이지 감지 [${link.source}]: "${link.text}" → ${link.href}`);
          const extracted = await extractNotionPage(page, link.href);
          // 짧은 페이지도 정상 결과다 — 길이로 거르지 않는다
          if (extracted.ok && extracted.markdown && extracted.markdown.length > 0) {
            result.pageUrl = extracted.url;
            result.pageTitle = extracted.title || link.text;
            result.markdown = extracted.markdown;
            console.log(`페이지 추출 완료: "${result.pageTitle}" — ${extracted.blockCount}블록 → 마크다운 ${extracted.markdown.length}자`);
          } else {
            console.warn(`페이지 추출 실패/내용 부족: ${extracted.reason || extracted.markdown?.length + '자'}`);
          }
        } else {
          console.log('페이지 생성 신호는 있었지만 링크를 찾지 못함 — 텍스트 응답으로 처리');
        }
      } catch (e: any) {
        console.warn('아티팩트 추출 중 오류:', e.message);
      }
    }

    return result;
  }
}

/** 브라우저를 새로 열고 닫으면서 한 번에 실행하는 기존 진입점 (CLI 기본 사용). */
export async function askNotionAi(prompt: string, options: NotionAiOptions = {}): Promise<NotionAiResult> {
  const profileDir = options.profileDir || PROFILE_DIR;
  const headless = options.headless ?? false;

  const browser = await chromium.launchPersistentContext(profileDir, {
    headless,
    viewport: { width: 1280, height: 900 },
  });
  const page = browser.pages()[0] || await browser.newPage();

  // tsx/esbuild가 keepNames로 삽입하는 __name 헬퍼는 브라우저 컨텍스트에 없다.
  // page.evaluate로 넘긴 함수 안에서 ReferenceError가 나므로 shim을 미리 주입한다.
  await page.addInitScript({ content: 'globalThis.__name = globalThis.__name || ((f) => f);' });
  await page.evaluate('globalThis.__name = globalThis.__name || ((f) => f)').catch(() => {});

  try {
    console.log('Notion AI 페이지로 이동...');
    // 로그인 보장 — 미로그인 상태면 여기서 명확히 실패하거나 사람이 로그인할 때까지 기다린다
    await ensureLoggedIn(page, { headless });
    await page.waitForSelector(SEL.modelButton, { timeout: 20000 });

    return await runPrompt(page, browser, prompt, options);
  } finally {
    await browser.close().catch(() => {});
  }
}

// 직접 실행일 때만 CLI 진입점을 돈다. 가드가 없으면 interactive.ts처럼 이 파일에서
// runPrompt만 가져다 쓰려는 다른 스크립트가 import하는 순간 이 블록까지 같이 실행돼
// 같은 프로필로 두 번째 브라우저를 띄우려다 충돌한다 (실제로 겪은 버그).
const isMainModule = !!process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (isMainModule) {
// 직접 실행: npx tsx executor.ts <프롬프트 또는 @파일경로> [모델] [이미지경로]
const rawArg = process.argv[2] || '안녕하세요! 간단한 테스트입니다.';
const prompt = rawArg.startsWith('@') ? fs.readFileSync(rawArg.slice(1), 'utf8') : rawArg;
const model = process.argv[3] || 'Fable 5';
const imagePath = process.argv[4] || '';

console.log(`모델: ${model} / 프롬프트 ${prompt.length}자`);
askNotionAi(prompt, { model, imagePath }).then(result => {
  fs.writeFileSync('last_result.txt', result.chatText, 'utf8');
  console.log('\n결과 저장: last_result.txt (채팅 응답)');

  if (result.markdown) {
    fs.writeFileSync('last_page.md', `# ${result.pageTitle}\n\n> 출처: ${result.pageUrl}\n\n${result.markdown}\n`, 'utf8');
    fs.writeFileSync('last_artifact.json',
      JSON.stringify({ url: result.pageUrl, title: result.pageTitle, markdownLength: result.markdown.length }, null, 2),
      'utf8');
    console.log('결과 저장: last_page.md (아티팩트 페이지 마크다운)');
    console.log('결과 저장: last_artifact.json (URL/제목)');
  }
}).catch(err => {
  console.error('\n❌ 실패:', err.message);
  process.exit(1);
});
}
