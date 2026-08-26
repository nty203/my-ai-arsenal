import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    result[argv[index].replace(/^--/, '')] = argv[index + 1] ?? '';
  }
  return result;
}

const args = parseArgs(process.argv.slice(2));
const action = args.action || 'Probe';
const profileDir = path.resolve(args.profileDir || 'browser-profile');
const browserPath = args.browserPath || undefined;
const projectRoot = args.projectRoot ? path.resolve(args.projectRoot) : '';
const prompt = args.prompt || '';
const sessionPath = path.resolve(args.sessionPath || path.join(profileDir, '..', 'chatgpt-browser-session.json'));
const timeoutMs = Number(args.timeoutMs || 45000);
const quietMs = Number(args.quietMs || 3000);
const pollMs = Math.max(250, Number(args.pollSeconds || 2) * 1000);
const startupTimeoutMs = Number(args.startupTimeoutSeconds || 180) * 1000;
const runTimeoutMs = Number(args.runTimeoutSeconds || 3600) * 1000;
const startResponseTimeoutMs = Number(args.startResponseTimeoutSeconds || 900) * 1000;
const startRetryCount = Math.max(1, Number(args.startRetryCount || 3));
const startRetryDelayMs = Math.max(0, Number(args.startRetryDelaySeconds || 5) * 1000);
const disconnectedGraceMs = Math.max(30, Number(args.disconnectedGraceSeconds || 120)) * 1000;
const staleHeartbeatMs = Math.max(60, Number(args.staleHeartbeatSeconds || 900)) * 1000;
const maxLoops = Math.max(0, Number(args.maxLoops || 0));

const runStatePath = projectRoot ? path.join(projectRoot, 'loop', 'RUN_STATE.md') : '';
const taskBoardPath = projectRoot ? path.join(projectRoot, 'docs', 'wiki', 'tasks', 'TASK_BOARD.md') : '';
const claimsPath = projectRoot ? path.join(projectRoot, 'docs', 'wiki', 'tasks', 'claims') : '';
const stopPath = projectRoot ? path.join(projectRoot, 'loop', 'STOP') : '';
const runtimePath = projectRoot ? path.join(projectRoot, 'loop', 'runtime') : path.dirname(sessionPath);
const statusPath = path.join(runtimePath, 'chatgpt-browser-loop.json');
const logPath = path.join(runtimePath, 'chatgpt-browser-loop.log');

const defaultPrompt = projectRoot
  ? `${projectRoot} 프로젝트에서 개발 계속. loop/EXECUTION.md와 loop/PROMPT.md를 먼저 읽고 chatgpt_remote 규약으로 정확히 한 iteration을 구현, 검증, 기록해. local AI CLI, push, deploy, credentials 접근은 금지한다.`
  : '';

function emit(value) {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function visible(locator) {
  return locator.isVisible().catch(() => false);
}

async function firstVisible(locator) {
  const count = await locator.count().catch(() => 0);
  for (let index = 0; index < count; index += 1) {
    const candidate = locator.nth(index);
    if (await visible(candidate)) return candidate;
  }
  return null;
}

async function launchPersistentBrowser() {
  fs.mkdirSync(profileDir, { recursive: true });
  const context = await chromium.launchPersistentContext(profileDir, {
    executablePath: browserPath,
    headless: false,
    viewport: null,
    locale: 'ko-KR',
    timezoneId: 'Asia/Seoul',
    args: [
      '--start-maximized',
      '--disable-blink-features=AutomationControlled',
      '--disable-session-crashed-bubble',
      '--disable-features=TranslateUI',
      '--no-first-run',
      '--no-default-browser-check',
      '--no-sandbox',
      '--disable-dev-shm-usage',
    ],
  });

  await context.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
  });

  const pages = context.pages().filter((page) => !page.isClosed());
  const page = pages[0] || await context.newPage();
  for (const extra of pages.slice(1)) await extra.close().catch(() => {});
  await page.goto('about:blank').catch(() => {});
  return { context, page };
}

async function getComposer(page, waitMs = timeoutMs) {
  const selectors = [
    '#prompt-textarea',
    'textarea#prompt-textarea',
    '[data-testid="composer-text-input"]',
    'div[contenteditable="true"][role="textbox"]',
    'div[contenteditable="true"]',
  ];
  const deadline = Date.now() + waitMs;
  while (Date.now() < deadline) {
    for (const selector of selectors) {
      const candidate = await firstVisible(page.locator(selector));
      if (candidate) return candidate;
    }
    await page.waitForTimeout(250);
  }
  throw new Error('ChatGPT web composer did not become available.');
}

async function waitStableComposer(page, waitMs = timeoutMs) {
  const deadline = Date.now() + waitMs;
  let previous = '';
  let stableCount = 0;
  while (Date.now() < deadline) {
    const composer = await getComposer(page, Math.min(5000, Math.max(1000, deadline - Date.now())));
    const box = await composer.boundingBox();
    const signature = box
      ? `${Math.round(box.x)},${Math.round(box.y)},${Math.round(box.width)},${Math.round(box.height)}`
      : '';
    stableCount = signature && signature === previous ? stableCount + 1 : 1;
    previous = signature;
    if (stableCount >= 3) return composer;
    await page.waitForTimeout(250);
  }
  throw new Error('ChatGPT web composer did not become stable.');
}

async function ensureAuthenticated(page, waitMs = timeoutMs) {
  const deadline = Date.now() + waitMs;
  while (Date.now() < deadline) {
    const composer = await firstVisible(page.locator('#prompt-textarea, textarea#prompt-textarea, div[contenteditable="true"]'));
    const profile = await firstVisible(page.locator('button[aria-label*="프로필" i], button[aria-label*="profile" i]'));
    const plugins = await firstVisible(page.locator('a[href="/plugins"], a[href^="/plugins/"]'));
    const login = await firstVisible(page.getByRole('button', { name: /로그인|log in|sign in/i }));
    if ((composer && !login) || profile || plugins) return;
    await page.waitForTimeout(500);
  }
  throw new Error('The selected persistent Chrome profile is not signed in to ChatGPT.');
}

async function openFreshChat(page) {
  await page.goto('about:blank', { waitUntil: 'load', timeout: 10000 }).catch(() => {});
  await page.goto('https://chatgpt.com/', { waitUntil: 'domcontentloaded', timeout: 60000 });
  await ensureAuthenticated(page, timeoutMs);
  return waitStableComposer(page, timeoutMs);
}

function selectedState(attributes) {
  return attributes['aria-selected'] === 'true'
    || attributes['aria-checked'] === 'true'
    || attributes['aria-pressed'] === 'true'
    || ['active', 'checked', 'on', 'selected'].includes(attributes['data-state']);
}

async function modeMetadata(page) {
  return page.evaluate(() => {
    const visibleElement = (element) => {
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
    };
    const values = [];
    for (const element of document.querySelectorAll('button, [role="tab"], [role="radio"]')) {
      const text = (element.textContent || '').replace(/\s+/g, ' ').trim();
      if (!/^(Chat|Work)$/i.test(text) || !visibleElement(element)) continue;
      const rect = element.getBoundingClientRect();
      values.push({
        tag: element.tagName.toLowerCase(),
        role: element.getAttribute('role') || '',
        text,
        ariaSelected: element.getAttribute('aria-selected') || '',
        ariaChecked: element.getAttribute('aria-checked') || '',
        ariaPressed: element.getAttribute('aria-pressed') || '',
        dataState: element.getAttribute('data-state') || '',
        className: String(element.className || '').slice(0, 180),
        x: Math.round(rect.x),
        y: Math.round(rect.y),
        width: Math.round(rect.width),
        height: Math.round(rect.height),
      });
    }
    return values;
  });
}

async function ensureChatMode(page) {
  const exactChat = page.locator('button, [role="tab"], [role="radio"]').filter({ hasText: /^\s*Chat\s*$/i });
  const chat = await firstVisible(exactChat);
  if (chat) {
    await chat.scrollIntoViewIfNeeded().catch(() => {});
    await chat.click({ timeout: 5000 });
    await page.waitForTimeout(500);
  }

  const metadata = await modeMetadata(page);
  const chatState = metadata.find((item) => /^Chat$/i.test(item.text));
  const workState = metadata.find((item) => /^Work$/i.test(item.text));
  const chatSelected = chatState && selectedState({
    'aria-selected': chatState.ariaSelected,
    'aria-checked': chatState.ariaChecked,
    'aria-pressed': chatState.ariaPressed,
    'data-state': chatState.dataState,
  });
  const workSelected = workState && selectedState({
    'aria-selected': workState.ariaSelected,
    'aria-checked': workState.ariaChecked,
    'aria-pressed': workState.ariaPressed,
    'data-state': workState.dataState,
  });
  if (workSelected && !chatSelected) throw new Error('Work mode remained selected after the Chat DOM event.');
  return { clicked: Boolean(chat), metadata };
}

async function clearComposer(composer) {
  await composer.click({ timeout: 5000 });
  await composer.press('Control+A');
  await composer.press('Backspace');
}

async function composerText(composer) {
  return composer.evaluate((element) => (element.innerText || element.textContent || element.value || '').trim()).catch(() => '');
}

async function pluginTokenIsCommitted(page) {
  const composer = await getComposer(page, 5000);
  const box = await composer.boundingBox();
  const strong = page.locator('a[href*="/plugins/"]').filter({ hasText: /^\s*AI Folder Remote\s*$/i });
  if (await firstVisible(strong)) return true;

  const candidates = page.locator('[data-testid*="plugin" i], button, [role="button"]')
    .filter({ hasText: /^\s*AI Folder Remote\s*$/i });
  const count = await candidates.count().catch(() => 0);
  for (let index = 0; index < count; index += 1) {
    const candidate = candidates.nth(index);
    if (!(await visible(candidate))) continue;
    const inMenu = await candidate.evaluate((element) => Boolean(element.closest('[role="menu"], [role="listbox"]'))).catch(() => true);
    if (inMenu) continue;
    const candidateBox = await candidate.boundingBox();
    if (!box || !candidateBox || Math.abs(candidateBox.y - box.y) < 260) return true;
  }
  return false;
}

async function plusButtonMetadata(page) {
  return page.evaluate(() => {
    const values = [];
    for (const element of document.querySelectorAll('button')) {
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      if (rect.width <= 0 || rect.height <= 0 || style.display === 'none' || style.visibility === 'hidden') continue;
      const name = (element.getAttribute('aria-label') || element.textContent || '').replace(/\s+/g, ' ').trim();
      const testId = element.getAttribute('data-testid') || '';
      if (!/추가|파일|도구|attach|add|upload|composer.*plus/i.test(`${name} ${testId}`)) continue;
      values.push({
        name: name.slice(0, 160),
        testId,
        x: Math.round(rect.x),
        y: Math.round(rect.y),
        width: Math.round(rect.width),
        height: Math.round(rect.height),
      });
    }
    return values;
  });
}

async function findComposerPlusButton(page, composer) {
  const selectors = [
    'button[data-testid="composer-plus-btn"]',
    'button[data-testid*="composer" i][data-testid*="plus" i]',
    'button[aria-label*="파일 등 추가" i]',
    'button[aria-label*="파일 추가" i]',
    'button[aria-label*="도구" i]',
    'button[aria-label*="attach" i]',
    'button[aria-label*="add files" i]',
    'button[aria-label*="upload" i]',
  ];
  const composerBox = await composer.boundingBox();
  const matches = [];
  for (const selector of selectors) {
    const locator = page.locator(selector);
    const count = await locator.count().catch(() => 0);
    for (let index = 0; index < count; index += 1) {
      const candidate = locator.nth(index);
      if (!(await visible(candidate))) continue;
      const box = await candidate.boundingBox();
      const distance = composerBox && box
        ? Math.abs((box.y + box.height / 2) - (composerBox.y + composerBox.height / 2))
        : Number.MAX_SAFE_INTEGER;
      matches.push({ candidate, distance });
    }
  }
  matches.sort((left, right) => left.distance - right.distance);
  return matches[0]?.candidate || null;
}

async function pluginMenuRows(page) {
  const selectors = ['[role="menuitem"]', '[role="option"]', '[role="listitem"]', 'button', 'a'];
  const matches = [];
  for (const selector of selectors) {
    const locator = page.locator(selector).filter({ hasText: /AI Folder Remote/i });
    const count = await locator.count().catch(() => 0);
    for (let index = 0; index < count; index += 1) {
      const candidate = locator.nth(index);
      if (!(await visible(candidate))) continue;
      const text = (await candidate.innerText().catch(() => '')).replace(/\s+/g, ' ').trim();
      if (!/^AI Folder Remote(?:\s|$)/i.test(text) || text.length > 260) continue;
      const box = await candidate.boundingBox();
      if (!box) continue;
      matches.push({ candidate, area: box.width * box.height, text });
    }
  }
  matches.sort((left, right) => left.area - right.area);
  return matches;
}

async function menuDiagnostics(page, composer) {
  const plus = await findComposerPlusButton(page, composer);
  if (plus) {
    await plus.click({ timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(700);
  }
  return page.evaluate(() => {
    const visibleElement = (element) => {
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
    };
    const values = [];
    for (const element of document.querySelectorAll('[role="menuitem"], [role="option"], [role="listitem"], [role="menu"], [role="listbox"], button, a')) {
      if (!visibleElement(element)) continue;
      const text = (element.textContent || '').replace(/\s+/g, ' ').trim();
      const label = (element.getAttribute('aria-label') || '').trim();
      if (!text && !label) continue;
      const rect = element.getBoundingClientRect();
      if (rect.y < window.innerHeight * 0.45 && !/AI Folder|플러그인|plugin/i.test(`${text} ${label}`)) continue;
      values.push({
        tag: element.tagName.toLowerCase(),
        role: element.getAttribute('role') || '',
        text: text.slice(0, 220),
        label: label.slice(0, 160),
        testId: element.getAttribute('data-testid') || '',
        x: Math.round(rect.x),
        y: Math.round(rect.y),
        width: Math.round(rect.width),
        height: Math.round(rect.height),
      });
      if (values.length >= 80) break;
    }
    return values;
  });
}

async function selectRemotePlugin(page, composer) {
  await clearComposer(composer);
  if (await pluginTokenIsCommitted(page)) return;

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const plus = await findComposerPlusButton(page, composer);
    if (!plus) throw new Error('The ChatGPT composer + button was not found through DOM selectors.');
    await plus.scrollIntoViewIfNeeded().catch(() => {});
    await plus.click({ timeout: 5000 });
    await page.waitForTimeout(1000);

    // Type into the search box (which is automatically focused)
    await page.keyboard.type('AI Folder Remote', { delay: 50 });
    await page.waitForTimeout(2000);

    // Press Enter to select the filtered option
    await page.keyboard.press('Enter');
    await page.waitForTimeout(1000);

    if (await pluginTokenIsCommitted(page)) return;
    await page.keyboard.press('Escape'); // close menu if still open
    await page.waitForTimeout(500);
  }
  throw new Error('AI Folder Remote was not committed as a plugin token; nothing was submitted.');
}

async function routeToChat(page, waitMs = 30000) {
  const deadline = Date.now() + waitMs;
  const pattern = /여기서.*채팅.*계속|채팅.*계속|continue.*chat|keep.*chat/i;
  while (Date.now() < deadline) {
    const button = await firstVisible(page.getByRole('button', { name: pattern }));
    if (button) {
      await button.click({ timeout: 5000 });
      return true;
    }
    await page.waitForTimeout(500);
  }
  return false;
}

async function sendPrompt(page, text) {
  let composer = await waitStableComposer(page, timeoutMs);
  const chatMode = await ensureChatMode(page);
  composer = await waitStableComposer(page, timeoutMs);
  await selectRemotePlugin(page, composer);
  composer = await getComposer(page, 5000);
  await composer.click({ timeout: 5000 });
  await page.keyboard.insertText(` ${text}`);
  if (!(await pluginTokenIsCommitted(page))) throw new Error('The plugin token disappeared before submit.');

  const sendSelectors = [
    'button[data-testid="send-button"]',
    'button[aria-label*="프롬프트 보내기" i]',
    'button[aria-label*="메시지 보내기" i]',
    'button[aria-label*="send prompt" i]',
    'button[aria-label*="send message" i]',
  ];
  let send = null;
  for (const selector of sendSelectors) {
    send = await firstVisible(page.locator(selector));
    if (send) break;
  }
  if (!send || !(await send.isEnabled().catch(() => false))) throw new Error('The ChatGPT send button was unavailable.');
  await send.click({ timeout: 5000 });

  const submitDeadline = Date.now() + 10000;
  let submitted = false;
  while (Date.now() < submitDeadline) {
    composer = await getComposer(page, 3000);
    const remaining = await composerText(composer);
    if (!remaining || remaining.length < Math.min(20, text.trim().length)) {
      submitted = true;
      break;
    }
    await page.waitForTimeout(300);
  }
  if (!submitted) throw new Error('The composer did not clear after the DOM submit event.');

  await routeToChat(page, 30000);
  await page.waitForTimeout(500);
  fs.mkdirSync(path.dirname(sessionPath), { recursive: true });
  fs.writeFileSync(sessionPath, JSON.stringify({ url: page.url(), updatedAt: new Date().toISOString() }, null, 2));
  return { chatMode, url: page.url() };
}

async function responseIsBusy(page) {
  const selectors = [
    'button[data-testid="stop-button"]',
    'button[aria-label*="생성 중지" i]',
    'button[aria-label*="응답 중지" i]',
    'button[aria-label*="stop generating" i]',
    'button[aria-label*="stop response" i]',
  ];
  for (const selector of selectors) {
    if (await firstVisible(page.locator(selector))) return true;
  }
  return false;
}

async function connectionLostVisible(page) {
  const notice = page.getByText(/연결이 끊어졌습니다|connection (?:was )?lost|disconnected/i);
  return Boolean(await firstVisible(notice));
}

async function stopResponse(page) {
  const selectors = [
    'button[data-testid="stop-button"]',
    'button[aria-label*="생성 중지" i]',
    'button[aria-label*="응답 중지" i]',
    'button[aria-label*="답변 중지" i]',
    'button[aria-label*="stop generating" i]',
    'button[aria-label*="stop response" i]',
  ];
  for (const selector of selectors) {
    const button = await firstVisible(page.locator(selector));
    if (!button) continue;
    await button.click({ timeout: 5000 });
    return true;
  }
  const named = await firstVisible(page.getByRole('button', { name: /답변 중지|응답 중지|생성 중지|stop (?:generating|response)/i }));
  if (!named) return false;
  await named.click({ timeout: 5000 });
  return true;
}

async function waitIdle(page, waitMs, stableQuietMs = quietMs) {
  const deadline = Date.now() + waitMs;
  let quietSince = 0;
  while (Date.now() < deadline) {
    if (await responseIsBusy(page)) quietSince = 0;
    else {
      if (!quietSince) quietSince = Date.now();
      if (Date.now() - quietSince >= stableQuietMs) return true;
    }
    await page.waitForTimeout(500);
  }
  return false;
}

function getRunField(markdown, name) {
  const expression = new RegExp(`^- ${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}:\\s*(.*)$`, 'mi');
  return markdown.match(expression)?.[1]?.trim() || '';
}

function snapshot() {
  const markdown = fs.readFileSync(runStatePath, 'utf8');
  return {
    state: getRunField(markdown, 'state'),
    active_task: getRunField(markdown, 'active_task'),
    run_id: getRunField(markdown, 'run_id'),
    heartbeat_at: getRunField(markdown, 'heartbeat_at'),
    circuit_open: getRunField(markdown, 'circuit_open'),
    last_result: getRunField(markdown, 'last_result'),
    last_error: getRunField(markdown, 'last_error'),
  };
}

function claimSignature() {
  if (!claimsPath || !fs.existsSync(claimsPath)) return '';
  return fs.readdirSync(claimsPath, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => {
      const stat = fs.statSync(path.join(claimsPath, entry.name));
      return `${entry.name}:${stat.size}:${stat.mtimeMs}`;
    })
    .sort()
    .join('|');
}

function allTasksDone() {
  if (!fs.existsSync(taskBoardPath)) return false;
  const statuses = [...fs.readFileSync(taskBoardPath, 'utf8').matchAll(/^\|\s*[^|]+\s*\|\s*(BLOCKED|READY|CLAIMED|IN_PROGRESS|REVIEW|DONE)\s*\|/gmi)]
    .map((match) => match[1].toUpperCase());
  return statuses.length > 0 && statuses.every((status) => status === 'DONE');
}

function gracefulStopRequested() {
  return fs.existsSync(stopPath);
}

function hardStopRequested(current = snapshot()) {
  return current.circuit_open.toLowerCase() === 'true'
    || /^(CIRCUIT_OPEN|PAUSED)$/i.test(current.state);
}


function heartbeatIsStale(current) {
  const timestamp = Date.parse(current.heartbeat_at);
  return !Number.isFinite(timestamp) || Date.now() - timestamp >= staleHeartbeatMs;
}

function writeStatus(phase, loop, current, message) {
  fs.mkdirSync(runtimePath, { recursive: true });
  const status = {
    pid: process.pid,
    phase,
    loop,
    updated_at: new Date().toISOString(),
    project_root: projectRoot,
    profile_dir: profileDir,
    state: current.state,
    active_task: current.active_task,
    run_id: current.run_id,
    last_result: current.last_result,
    message,
  };
  fs.writeFileSync(statusPath, JSON.stringify(status, null, 2));
  fs.appendFileSync(logPath, `${status.updated_at} phase=${phase} loop=${loop} state=${current.state} message=${message}\n`);
  emit(status);
}

async function waitUntil(predicate, waitMs) {
  const deadline = Date.now() + waitMs;
  while (Date.now() < deadline) {
    const current = snapshot();
    if (hardStopRequested(current)) return false;
    if (await predicate(current)) return true;
    await sleep(pollMs);
  }
  return false;
}

function startHandshakeAdvanced(current, baseline, staleResume) {
  if (!/^(RUNNING|RECOVERING)$/i.test(current.state)) return false;
  if (!staleResume) return true;
  const sameClaim = current.active_task === baseline.active_task && current.run_id === baseline.run_id;
  return sameClaim && current.heartbeat_at && current.heartbeat_at !== baseline.heartbeat_at;
}

async function waitForStart(baseline, staleResume) {
  return waitUntil((current) => startHandshakeAdvanced(current, baseline, staleResume), startupTimeoutMs);
}

function terminalResultAdvanced(current, baseline) {
  return !/^(RUNNING|RECOVERING)$/i.test(current.state)
    && Boolean(current.last_result)
    && current.last_result !== baseline.last_result;
}

function baselineStillUnchanged(current, baseline) {
  return current.state === baseline.state
    && current.active_task === baseline.active_task
    && current.run_id === baseline.run_id
    && current.heartbeat_at === baseline.heartbeat_at
    && current.last_result === baseline.last_result;
}

async function waitForStartResponse(page, baseline, staleResume, baselineClaims, loop) {
  const deadline = Date.now() + startResponseTimeoutMs;
  let quietSince = 0;
  let disconnectedSince = 0;

  while (Date.now() < deadline) {
    const current = snapshot();
    if (hardStopRequested(current)) return { kind: 'stopped', current };
    if (startHandshakeAdvanced(current, baseline, staleResume)) return { kind: 'started', current };
    if (terminalResultAdvanced(current, baseline)) return { kind: 'terminal', current };

    const busy = await responseIsBusy(page);
    if (!busy) {
      disconnectedSince = 0;
      if (!quietSince) quietSince = Date.now();
      if (Date.now() - quietSince >= quietMs) return { kind: 'idle', current };
    } else {
      quietSince = 0;
      if (await connectionLostVisible(page)) {
        if (!disconnectedSince) disconnectedSince = Date.now();
        const safeToAbort = baselineStillUnchanged(current, baseline) && claimSignature() === baselineClaims;
        if (safeToAbort && Date.now() - disconnectedSince >= disconnectedGraceMs) {
          const stopped = await stopResponse(page).catch(() => false);
          if (stopped) {
            writeStatus('DISCONNECTED_ABORT', loop, current, 'ChatGPT stayed disconnected before creating a claim or RUN_STATE handshake; stopped the response with a DOM event so a retry is safe.');
            await waitIdle(page, 15000, quietMs);
            return { kind: 'disconnected', current: snapshot() };
          }
        }
      } else {
        disconnectedSince = 0;
      }
    }
    await page.waitForTimeout(500);
  }
  const current = snapshot();
  if (hardStopRequested(current)) return { kind: 'stopped', current };
  if (startHandshakeAdvanced(current, baseline, staleResume)) return { kind: 'started', current };
  if (terminalResultAdvanced(current, baseline)) return { kind: 'terminal', current };
  if (!(await responseIsBusy(page))) return { kind: 'idle', current };
  writeStatus('START_RESPONSE_WATCH', loop, current,
    'ChatGPT is still actively generating after one watch window; keep watching the same response. Timeout alone never authorizes a stop or fresh-chat retry.');
  return waitForStartResponse(page, baseline, staleResume, baselineClaims, loop);
}

async function runContinuous(page) {
  if (!projectRoot || !fs.existsSync(runStatePath)) throw new Error(`RUN_STATE is missing: ${runStatePath}`);
  let loop = 0;
  let projectComplete = false;

  while (true) {
    let current = snapshot();
    if (hardStopRequested(current)) break;
    if (gracefulStopRequested() && !/^(RUNNING|RECOVERING)$/i.test(current.state)) {
      writeStatus('GRACEFUL_STOP', loop, current, 'loop/STOP is present; no new ChatGPT iteration will be opened.');
      break;
    }
    if (/^(SKIP|BLOCKED|FAIL)/i.test(current.last_result || '')) {
      writeStatus('STOPPED', loop, current,
        `Terminal task result ${current.last_result} is recorded; no recovery or replacement chat will be opened.`);
      break;
    }
    if (allTasksDone()) {
      projectComplete = true;
      writeStatus('PROJECT_COMPLETE', loop, current, 'All recognized Task Board rows are DONE; no new ChatGPT chat will be opened.');
      break;
    }
    if (maxLoops > 0 && loop >= maxLoops) break;

    let staleResume = false;
    if (/^(RUNNING|RECOVERING)$/i.test(current.state)) {
      staleResume = heartbeatIsStale(current) && !(await responseIsBusy(page));
      if (!staleResume) {
        writeStatus('WAIT_EXISTING', loop, current, 'Waiting for the active ChatGPT iteration to finish.');
        const waitDeadline = Date.now() + runTimeoutMs;
        let finished = false;
        while (Date.now() < waitDeadline) {
          const remainingMs = Math.max(1, waitDeadline - Date.now());
          finished = await waitUntil(
            (next) => !/^(RUNNING|RECOVERING)$/i.test(next.state),
            Math.min(30000, remainingMs),
          );
          if (finished) break;

          current = snapshot();
          if (heartbeatIsStale(current) && !(await responseIsBusy(page))) {
            staleResume = true;
            writeStatus('RECOVER_STALE', loop, current,
              `Active ${current.active_task || 'task'} stopped updating and its ChatGPT response is idle; resuming the existing claim in a fresh chat.`);
            break;
          }
        }
        if (staleResume) {
          // Fall through to the guarded existing-claim recovery path below.
        } else if (!finished) {
          writeStatus('WATCH_EXISTING_TIMEOUT', loop, snapshot(),
            'Existing iteration exceeded one watch window; keeping the continuous loop alive and re-evaluating instead of exiting.');
          continue;
        } else {
          continue;
        }
      }
      if (staleResume) {
        writeStatus('RECOVER_STALE', loop, current, `Resuming stale ${current.active_task || 'active task'} in a fresh chat without creating a new claim.`);
      }
    } else if (current.state && current.state.toUpperCase() !== 'IDLE') {
      writeStatus('STOPPED', loop, current, `State is not runnable: ${current.state}`);
      break;
    }

    loop += 1;
    const baseline = current;
    let started = false;
    let completedDuringStart = false;
    for (let attempt = 1; attempt <= startRetryCount && !started; attempt += 1) {
      current = snapshot();
      writeStatus('LAUNCHING', loop, current, `Opening a fresh ChatGPT DOM-controlled web chat (attempt ${attempt}/${startRetryCount}).`);
      const baselineClaims = claimSignature();
      try {
        await openFreshChat(page);
        const iterationPrompt = staleResume
          ? `기존 RUN_STATE의 active_task와 claim만 이어서 복구해. 새 task나 claim은 만들지 마. ${prompt || defaultPrompt}`
          : (prompt || defaultPrompt);
        await sendPrompt(page, iterationPrompt);
      } catch (error) {
        writeStatus('START_RETRY', loop, snapshot(), `Browser submit failed on attempt ${attempt}/${startRetryCount}: ${error.message}`);
        if (attempt < startRetryCount) await sleep(startRetryDelayMs);
        continue;
      }

      started = await waitForStart(baseline, staleResume);
      if (started) break;

      current = snapshot();
      if (terminalResultAdvanced(current, baseline)) {
        started = true;
        completedDuringStart = true;
        writeStatus('TERMINAL_HANDSHAKE', loop, current, 'The submitted iteration completed before a start handshake was observed; accepting the advanced terminal result without retry.');
        break;
      }

      if (await responseIsBusy(page)) {
        writeStatus('WAIT_START_RESPONSE', loop, snapshot(), 'No RUN_STATE handshake yet; waiting for the submitted response before deciding whether retry is safe.');
        const response = await waitForStartResponse(page, baseline, staleResume, baselineClaims, loop);
        if (response.kind === 'stopped') return;
        if (response.kind === 'started') {
          started = true;
          break;
        }
        if (response.kind === 'terminal') {
          started = true;
          completedDuringStart = true;
          writeStatus('TERMINAL_HANDSHAKE', loop, response.current, 'The submitted iteration completed while waiting for the start response; no duplicate fresh chat will be opened.');
          break;
        }
        started = await waitForStart(baseline, staleResume);
        if (started) break;
        current = snapshot();
        if (terminalResultAdvanced(current, baseline)) {
          started = true;
          completedDuringStart = true;
          writeStatus('TERMINAL_HANDSHAKE', loop, current, 'The submitted iteration completed while waiting for UI idle; no duplicate fresh chat will be opened.');
          break;
        }
      }

      current = snapshot();
      if (terminalResultAdvanced(current, baseline)) {
        started = true;
        completedDuringStart = true;
        writeStatus('TERMINAL_HANDSHAKE', loop, current, 'The submitted iteration published a new terminal result; no duplicate fresh chat will be opened.');
        break;
      }

      if (attempt < startRetryCount) {
        writeStatus('START_RETRY', loop, snapshot(), `No verified RUNNING/RECOVERING handshake on attempt ${attempt}/${startRetryCount}; retrying in a fresh chat.`);
        await sleep(startRetryDelayMs);
      }
    }

    if (!started) {
      writeStatus('START_FAILED', loop, snapshot(), `ChatGPT failed to start the iteration after ${startRetryCount} attempts.`);
      break;
    }

    if (!completedDuringStart) {
      writeStatus('RUNNING', loop, snapshot(), 'ChatGPT iteration started with a verified RUN_STATE handshake.');
    }
    const completed = completedDuringStart || await waitUntil((next) => {
        if (/^(SKIP|BLOCKED|FAIL)/i.test(next.last_result || '')) return true;
        if (/^(RUNNING|RECOVERING)$/i.test(next.state)) return false;
        if (next.circuit_open.toLowerCase() === 'true') return true;
        return terminalResultAdvanced(next, baseline);
      }, runTimeoutMs);

    const final = snapshot();
    if (!completed) {
      writeStatus('RUN_TIMEOUT_RECOVERABLE', loop, final,
        'ChatGPT iteration exceeded one run watch window; preserving RUN_STATE and re-evaluating for stale-claim recovery instead of exiting.');
      continue;
    }

    writeStatus('WAIT_UI_IDLE', loop, final, 'Project closeout is terminal; waiting for the current ChatGPT response to finish.');
    let uiIdle = await waitIdle(page, startResponseTimeoutMs, quietMs);
    while (!uiIdle) {
      writeStatus('UI_IDLE_WATCH', loop, snapshot(),
        'Terminal project state is published, but the ChatGPT response is still active; keep watching it. Do not press Stop merely to advance the loop.');
      await sleep(5000);
      uiIdle = await waitIdle(page, startResponseTimeoutMs, quietMs);
    }
    writeStatus('COMPLETED', loop, final, 'Iteration closeout and ChatGPT response completed; evaluating the next fresh chat.');
    if (final.circuit_open.toLowerCase() === 'true' || /^CIRCUIT_OPEN$/i.test(final.state)) break;
    if (/^(SKIP|BLOCKED|FAIL)/i.test(final.last_result)) break;
    if (final.state.toUpperCase() !== 'IDLE') break;
  }

  if (!projectComplete) writeStatus('STOPPED', loop, snapshot(), 'Persistent-profile browser loop exited cleanly.');
}

async function run() {
  const { context, page } = await launchPersistentBrowser();
  try {
    if (action === 'Setup') {
      await page.goto('https://chatgpt.com/', { waitUntil: 'domcontentloaded', timeout: 60000 });
      await ensureAuthenticated(page, Number(args.timeoutMs || 600000));
      await waitStableComposer(page, Number(args.timeoutMs || 600000));
      emit({ action, ready: true, profileDir });
      return;
    }
    if (action === 'Probe') {
      await openFreshChat(page);
      const chatMode = await ensureChatMode(page);
      const composer = await waitStableComposer(page, timeoutMs);
      let pluginSelected = false;
      let pluginError = '';
      try {
        await selectRemotePlugin(page, composer);
        pluginSelected = await pluginTokenIsCommitted(page);
      } catch (error) {
        pluginError = error.message;
      }
      let menu = [];
      let screenshot = '';
      if (!pluginSelected) {
        menu = await menuDiagnostics(page, composer);
        screenshot = path.join(runtimePath, 'chatgpt-browser-probe.png');
        fs.mkdirSync(runtimePath, { recursive: true });
        await page.screenshot({ path: screenshot, fullPage: false }).catch(() => { screenshot = ''; });
      }
      emit({
        action,
        authenticated: true,
        chatMode,
        plusButtons: await plusButtonMetadata(page),
        pluginSelected,
        pluginError,
        menu,
        screenshot,
      });
      if (!pluginSelected) throw new Error(pluginError || 'AI Folder Remote was not selected.');
      return;
    }
    if (action === 'Prompt') {
      if (!(prompt || defaultPrompt).trim()) throw new Error('Prompt is required.');
      await openFreshChat(page);
      const result = await sendPrompt(page, prompt || defaultPrompt);
      emit({ action, submitted: true, pluginVerified: true, url: result.url });
      return;
    }
    if (action === 'WaitIdle') {
      if (fs.existsSync(sessionPath)) {
        const saved = JSON.parse(fs.readFileSync(sessionPath, 'utf8'));
        if (saved.url) await page.goto(saved.url, { waitUntil: 'domcontentloaded', timeout: 60000 });
      }
      if (!(await waitIdle(page, timeoutMs, quietMs))) throw new Error('ChatGPT web response did not become idle before timeout.');
      emit({ action, idle: true });
      return;
    }
    if (action === 'StopDisconnected') {
      if (fs.existsSync(sessionPath)) {
        const saved = JSON.parse(fs.readFileSync(sessionPath, 'utf8'));
        if (saved.url) await page.goto(saved.url, { waitUntil: 'domcontentloaded', timeout: 60000 });
      }
      const current = snapshot();
      if (!(await responseIsBusy(page)) || !(await connectionLostVisible(page))) {
        throw new Error('The saved ChatGPT response is not both busy and disconnected; refusing to stop it.');
      }
      if (!baselineStillUnchanged(snapshot(), current)) {
        throw new Error('RUN_STATE changed while checking the disconnected response; refusing to stop it.');
      }
      if (!(await stopResponse(page))) throw new Error('The disconnected ChatGPT stop button was unavailable.');
      if (!(await waitIdle(page, 15000, quietMs))) throw new Error('The disconnected ChatGPT response did not stop cleanly.');
      emit({ action, stopped: true, state: snapshot().state, claimSignature: claimSignature() });
      return;
    }
    if (action === 'Loop') {
      await runContinuous(page);
      return;
    }
    throw new Error(`Unknown action: ${action}`);
  } finally {
    await context.close().catch(() => {});
  }
}

run().catch((error) => {
  process.stderr.write(`ERROR: ${error.stack || error.message}\n`);
  process.exitCode = 1;
});
