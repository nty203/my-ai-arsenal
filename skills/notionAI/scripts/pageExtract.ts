/**
 * Notion 페이지 → 마크다운 추출 (MCP 불필요, 브라우저 DOM만 사용)
 *
 * 왜 필요한가: Notion AI가 만든 아티팩트를 가져오려고 Notion MCP에 의존하면
 * MCP가 없는 환경에서는 결과물을 아예 못 가져온다. 이 모듈은 Playwright가
 * 이미 열어둔 로그인 세션의 DOM을 그대로 읽어 마크다운으로 변환한다.
 *
 * 실측한 Notion DOM 특성 (2026-08):
 *  - 블록은 [data-block-id] + `notion-<type>-block` 클래스로 구분된다.
 *  - 블록은 중첩된다. 자기 텍스트만 얻으려면 자손 [data-block-id]를 제거하고 읽어야 한다.
 *  - 표에는 role="row"가 없다. 셀(.notion-table-cell-text)을 y좌표로 묶어 행을 복원해야 한다.
 *  - to_do 체크 상태는 aria-checked가 없다. 텍스트의 line-through 여부로 판정한다.
 */

import { assertLoggedIn } from './session.js';

/** 페이지 안에서 실행되어 마크다운 문자열을 만드는 함수 (문자열로 주입 — 번들러 변환 회피) */
const EXTRACT_FN = `(() => {
  var root = document.querySelector('.notion-page-content');
  if (!root) return { ok: false, reason: 'no .notion-page-content' };

  var titleEl = document.querySelector('.notion-page-block [placeholder], h1');
  var title = titleEl ? (titleEl.innerText || '').trim() : document.title.replace(/\\s*\\|.*$/, '').trim();

  var consumed = new Set();

  function clean(s) {
    // NBSP → 일반 공백, 제로폭 문자(Notion이 빈 줄 유지용으로 심음) 제거
    return (s || '').replace(/\\u00a0/g, ' ').replace(/[\\u200b\\u200c\\ufeff]/g, '');
  }

  function ownText(el) {
    var clone = el.cloneNode(true);
    var nested = clone.querySelectorAll('[data-block-id]');
    for (var i = 0; i < nested.length; i++) nested[i].remove();
    return clean(clone.innerText).trim();
  }

  function typeOf(el) {
    var cls = String(el.className || '');
    var m = cls.match(/notion-([a-z_]+)-block/);
    return m ? m[1] : '';
  }

  function listDepth(el) {
    // 조상 중 리스트류 블록 개수 = 들여쓰기 단계
    var d = 0, cur = el.parentElement;
    while (cur && cur !== root) {
      if (cur.hasAttribute && cur.hasAttribute('data-block-id')) {
        var t = typeOf(cur);
        if (t === 'to_do' || t === 'bulleted_list' || t === 'numbered_list' || t === 'toggle') d++;
      }
      cur = cur.parentElement;
    }
    return d;
  }

  function isChecked(el) {
    // 완료된 to_do는 본문에 line-through가 적용된다
    var textEl = el.querySelector('[placeholder], .notranslate');
    if (!textEl) return false;
    try {
      var dec = window.getComputedStyle(textEl).textDecorationLine || '';
      return dec.indexOf('line-through') !== -1;
    } catch (e) { return false; }
  }

  function renderTable(el) {
    var cells = Array.prototype.slice.call(el.querySelectorAll('.notion-table-cell-text'));
    if (!cells.length) return '';
    // role="row"가 없으므로 y좌표(반올림)로 행을 복원한다
    var rows = [];
    var byY = {};
    for (var i = 0; i < cells.length; i++) {
      var r = cells[i].getBoundingClientRect();
      var key = Math.round(r.top / 4) * 4;
      if (!byY[key]) { byY[key] = []; rows.push(key); }
      byY[key].push({ x: r.left, text: clean(cells[i].innerText).replace(/\\s+/g, ' ').trim() });
    }
    rows.sort(function (a, b) { return a - b; });
    var out = [];
    for (var j = 0; j < rows.length; j++) {
      var row = byY[rows[j]].sort(function (a, b) { return a.x - b.x; });
      out.push('| ' + row.map(function (c) { return c.text.replace(/\\|/g, '\\\\|'); }).join(' | ') + ' |');
      if (j === 0) out.push('|' + row.map(function () { return '---'; }).join('|') + '|');
    }
    return out.join('\\n');
  }

  var lines = [];
  var blocks = Array.prototype.slice.call(root.querySelectorAll('[data-block-id]'));

  for (var i = 0; i < blocks.length; i++) {
    var el = blocks[i];
    if (consumed.has(el)) continue;

    var type = typeOf(el);

    if (type === 'table') {
      // 표는 최상위 표 블록만 처리하고 내부 블록은 전부 소비 처리
      var md = renderTable(el);
      if (md) {
        // 표 앞에 빈 줄이 없으면 마크다운 파서가 표로 인식하지 못한다
        if (lines.length && lines[lines.length - 1] !== '') lines.push('');
        lines.push(md, '');
      }
      var inner = el.querySelectorAll('[data-block-id]');
      for (var k = 0; k < inner.length; k++) consumed.add(inner[k]);
      consumed.add(el);
      continue;
    }

    if (type === 'divider') { lines.push('---', ''); continue; }

    var text = ownText(el);
    if (!text) continue;

    var depth = listDepth(el);
    var indent = new Array(depth + 1).join('  ');

    // 제목 앞에는 반드시 빈 줄 (바로 위가 목록이면 파서가 제목을 못 알아보는 경우가 있다)
    if (type === 'header' || type === 'sub_header' || type === 'sub_sub_header') {
      if (lines.length && lines[lines.length - 1] !== '') lines.push('');
    }

    if (type === 'header') lines.push('# ' + text, '');
    else if (type === 'sub_header') lines.push('## ' + text, '');
    else if (type === 'sub_sub_header') lines.push('### ' + text, '');
    else if (type === 'to_do') lines.push(indent + '- [' + (isChecked(el) ? 'x' : ' ') + '] ' + text);
    else if (type === 'bulleted_list') lines.push(indent + '- ' + text);
    else if (type === 'numbered_list') lines.push(indent + '1. ' + text);
    else if (type === 'toggle') lines.push(indent + '- ' + text);
    else if (type === 'quote') lines.push('> ' + text.replace(/\\n/g, '\\n> '), '');
    else if (type === 'callout') lines.push('> ' + text.replace(/\\n/g, '\\n> '), '');
    else if (type === 'code') lines.push('\\u0060\\u0060\\u0060', text, '\\u0060\\u0060\\u0060', '');
    else if (type === 'page') continue; // 하위 페이지 링크 카드는 건너뜀
    else lines.push(text, '');
  }

  // 연속 빈 줄 정리
  var body = lines.join('\\n').replace(/\\n{3,}/g, '\\n\\n').trim();
  return { ok: true, title: title, markdown: body, blockCount: blocks.length, rawLen: (root.innerText || '').length };
})()`;

export interface ExtractedPage {
  ok: boolean;
  reason?: string;
  url?: string;
  title?: string;
  markdown?: string;
  blockCount?: number;
  rawLen?: number;
}

/**
 * 지정한 Notion 페이지 URL을 열어 본문을 마크다운으로 추출한다.
 * Notion은 동적 렌더링이라 블록 수가 안정될 때까지 기다린다.
 */
export async function extractNotionPage(page: any, url: string): Promise<ExtractedPage> {
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.evaluate('globalThis.__name = globalThis.__name || ((f) => f)').catch(() => {});

  // 로그인이 풀렸으면 여기서 명확히 알려준다 (본문 대기 30초 헛돌지 않게)
  await page.waitForTimeout(2000);
  await assertLoggedIn(page);

  // 본문 렌더 대기
  await page.waitForSelector('.notion-page-content', { timeout: 30000 }).catch(() => {});

  // 블록 수가 2회 연속 동일해질 때까지 대기 (지연 렌더 대응)
  let prev = -1, stable = 0;
  for (let i = 0; i < 20; i++) {
    const n = await page.evaluate('document.querySelectorAll("[data-block-id]").length').catch(() => 0) as number;
    if (n === prev && n > 0) {
      if (++stable >= 2) break;
    } else {
      stable = 0;
      prev = n;
    }
    await page.waitForTimeout(1000);
  }

  // 내용이 더 안 늘어날 때까지 반복 추출.
  // AI가 만든 페이지는 채팅이 "완료"로 보인 뒤에도 본문이 계속 채워지는 경우가 있어,
  // 한 번만 읽으면 앞부분만 잘려 나온다 (실제로 84자만 얻은 적 있음).
  let best: ExtractedPage = { ok: false };
  let bestLen = 0;
  let stableReads = 0;

  for (let attempt = 0; attempt < 8; attempt++) {
    // 지연 로딩 블록을 강제로 렌더시키기 위해 끝까지 스크롤
    await page.evaluate(`(() => {
      var el = document.querySelector('.notion-frame, .notion-scroller, main') || document.scrollingElement;
      if (el) el.scrollTop = el.scrollHeight;
    })()`).catch(() => {});
    await page.waitForTimeout(1200);

    const r = await page.evaluate(EXTRACT_FN) as ExtractedPage;
    const len = r.markdown ? r.markdown.length : 0;

    if (len > bestLen) {
      best = r;
      bestLen = len;
      stableReads = 0;
    } else if (len > 0) {
      // 두 번 연속 안 늘어나면 완성된 것으로 본다
      if (++stableReads >= 2) break;
    }
    await page.waitForTimeout(1500);
  }

  return { ...best, url: page.url() };
}

/**
 * 응답 완료 후 "AI가 새로 만든 페이지" 링크를 찾는다.
 *
 * 기존 구현의 실패: 문서 전체의 a[href]를 프롬프트 전후로 diff했더니,
 * 사이드바 Recents가 사용 중 계속 바뀌는 바람에 전혀 무관한 기존 페이지를 집어왔다.
 * → 채팅 본문 영역(x>280) 링크를 1순위로 보고, 사이드바는 "응답 텍스트에 제목이
 *   등장하는 링크"만 인정하는 2순위 폴백으로 쓴다.
 */
export async function findArtifactLink(
  page: any,
  beforeHrefs: string[],
  responseText: string
): Promise<{ href: string; text: string; source: string } | null> {
  const candidates = await page.evaluate(`(() => {
    var out = [];
    var els = Array.prototype.slice.call(document.querySelectorAll('a[href]'));
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var r = el.getBoundingClientRect();
      out.push({
        href: el.href,
        text: (el.innerText || '').trim(),
        inChat: r.x > 280 && r.width > 0,
        // "notion-page-mention-token": AI가 대화 중 기존 페이지를 인라인으로
        // *언급*할 때 붙는 클래스. 새로 만든 아티팩트가 아니라 실측으로 확인됨
        // (예: 인사말에서 "개인 MM 입력 - 2026년 7월" 페이지를 예시로 언급한 링크가
        // 매번 오탐되던 원인).
        isMention: /notion-page-mention-token/.test(el.className || '')
      });
    }
    return out;
  })()`) as Array<{ href: string; text: string; inChat: boolean; isMention: boolean }>;

  const before = new Set(beforeHrefs);
  const norm = (s: string) => s.replace(/\s+/g, '').toLowerCase();
  const respNorm = norm(responseText);

  /**
   * "실제 Notion 페이지 URL"인지 판정.
   * 중요: 32자리 ID가 **경로(pathname)** 에 있어야 한다.
   * 대화 스레드 링크(`/chat?t=<32hex>#main`)는 ID가 쿼리에 있어서, 이 구분이 없으면
   * 접근성용 "Skip to content" 앵커를 아티팩트로 오탐한다 (실제로 겪은 버그).
   */
  const isPageUrl = (h: string): boolean => {
    try {
      const u = new URL(h);
      if (!/(^|\.)notion\.(so|com)$/.test(u.hostname)) return false;
      if (/^\/(chat|ai|login|signup|install|market)(\/|$)/.test(u.pathname)) return false;
      return /[0-9a-f]{32}/i.test(u.pathname);
    } catch {
      return false;
    }
  };

  // 링크 텍스트가 페이지 제목이 아닌 UI 문구인 경우 제외
  const isJunkText = (t: string) => !t || /^(skip to content|open page|new page|back)$/i.test(t.trim());

  const usable = candidates.filter(c => isPageUrl(c.href) && !c.isMention);

  // 1순위: 채팅 본문 영역 안의 "새로" 생긴 페이지 링크.
  // 주의: before에 없다고 fallback으로 기존 링크를 아무거나 집으면 안 된다 —
  // Notion AI가 인사말/제안 문구에서 기존 페이지("개인 MM 입력 - 2026년 7월" 등)를
  // 예시로 링크하는 경우가 있는데, 이건 AI가 새로 만든 아티팩트가 아니라 원래 있던
  // 페이지를 언급한 것뿐이다. 실제로 이 링크를 아티팩트로 오탐한 적이 있다.
  const inChat = usable.filter(c => c.inChat && !isJunkText(c.text) && !before.has(c.href));
  if (inChat.length) {
    const pick = inChat[inChat.length - 1];
    return { href: pick.href, text: pick.text, source: 'chat' };
  }

  // 2순위: 새로 생긴 링크 중, 그 제목이 응답 텍스트에도 등장하는 것
  const fresh = usable.filter(c => !before.has(c.href) && c.text.length > 3 && !isJunkText(c.text));
  const titleMatch = fresh.filter(c => respNorm.includes(norm(c.text)));
  if (titleMatch.length) {
    const pick = titleMatch[titleMatch.length - 1];
    return { href: pick.href, text: pick.text, source: 'sidebar+title' };
  }

  return null;
}
