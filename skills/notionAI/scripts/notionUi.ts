/**
 * Notion AI 채팅 UI 조작 공용 함수 (executor.ts / listModels.ts 공유).
 * 별도 모듈로 분리한 이유: executor.ts는 파일 하단에 "직접 실행" 블록이 있어서
 * 그대로 import하면 실행하지 않아도 프롬프트 전송까지 같이 돌아버린다.
 */

// Notion은 <button> 태그를 쓰지 않는다. 전부 div[role=button] 이다.
export const SEL = {
  modelButton: '[data-testid="unified-chat-model-button"]',
  sendButton: '[data-testid="agent-send-message-button"]',
  editor: 'div[contenteditable="true"], textarea',
};

/** 공백/개행을 모두 제거해 비교용으로 정규화.
 *  메뉴 항목의 textContent가 "Fable5Beta" 처럼 붙어 나오기 때문에 필요하다. */
export function norm(s: string): string {
  return (s || '').replace(/\s+/g, '').toLowerCase();
}

/** div[role=button] 을 실제 마우스 좌표 클릭. React 합성 이벤트를 확실히 발생시킨다. */
export async function clickBySelector(page: any, selector: string): Promise<boolean> {
  const box = await page.evaluate((sel: string) => {
    const el = document.querySelector(sel) as HTMLElement;
    if (!el) return null;
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) return null;
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, selector);
  if (!box) return false;
  await page.mouse.click(box.x, box.y);
  return true;
}

/**
 * 모델 드롭다운을 열어 스크롤하며 보이는 모든 항목의 라벨을 수집한다.
 * 목록이 길면 스크롤해야 뒷부분(예: GPT 계열)이 나타나므로, 더 이상 새 항목이
 * 안 나올 때까지(연속 3회 변화 없음) 스크롤을 반복한다.
 * 끝나면 Escape로 메뉴를 닫는다.
 */
export async function listAvailableModels(page: any): Promise<string[]> {
  const opened = await clickBySelector(page, SEL.modelButton);
  if (!opened) throw new Error(`모델 버튼(${SEL.modelButton})을 찾지 못했습니다.`);
  await page.waitForTimeout(1200);

  const seen = new Map<string, string>(); // norm(label) -> 원본 라벨
  let stableRounds = 0;
  for (let i = 0; i < 40 && stableRounds < 3; i++) {
    const items: string[] = await page.evaluate(`(() => {
      var items = Array.prototype.slice.call(document.querySelectorAll('[role="menuitem"]'));
      return items.map(function (e) { return e.innerText.replace(/\\s+/g, ' ').trim(); }).filter(Boolean);
    })()`);

    const before = seen.size;
    for (const label of items) {
      const key = norm(label);
      if (key && !seen.has(key)) seen.set(key, label);
    }
    stableRounds = seen.size === before ? stableRounds + 1 : 0;

    await page.mouse.move(900, 600);
    await page.mouse.wheel(0, 260);
    await page.waitForTimeout(350);
  }

  await page.keyboard.press('Escape').catch(() => {});
  return Array.from(seen.values());
}

/**
 * 목표 모델명과 버튼/메뉴에 보이는 라벨이 일치하는지 판정.
 * 양방향 부분일치인 이유: 드롭다운 메뉴엔 "Fable 5 Beta"로 나오지만 선택 후
 * 버튼에는 "Fable 5"처럼 태그가 생략된 축약형으로 표시되는 경우가 실측됨
 * (한쪽만 includes로는 이런 축약을 놓쳐 정상 선택인데도 검증 실패로 오탐했다).
 */
function matches(a: string, b: string): boolean {
  return a.includes(b) || b.includes(a);
}

/**
 * 모델을 선택하고, 실제로 선택됐는지 버튼 라벨을 다시 읽어 검증한다.
 * 검증에 실패하면 예외를 던진다 — 조용히 Auto 모델로 답변받는 사고를 막기 위함.
 */
export async function selectModel(page: any, targetModel: string): Promise<string> {
  const target = norm(targetModel); // 'Fable 5' -> 'fable5'

  const current = await page.evaluate((sel: string) =>
    (document.querySelector(sel) as HTMLElement)?.innerText?.trim() || '', SEL.modelButton);
  console.log(`현재 모델: "${current}" → 목표: "${targetModel}"`);

  if (matches(norm(current), target)) {
    console.log('이미 목표 모델 선택됨.');
    return current;
  }

  // 1) 모델 버튼 클릭 → 메뉴 열기
  const opened = await clickBySelector(page, SEL.modelButton);
  if (!opened) throw new Error(`모델 버튼(${SEL.modelButton})을 찾지 못했습니다.`);
  await page.waitForTimeout(1500);

  // 2) 메뉴 항목 탐색.
  //    메뉴는 스크롤 가능한 드롭다운이라 목표 항목이 보이는 영역 밖(클리핑)에 있을 수 있다.
  //    그 상태로 좌표 클릭하면 메뉴 바깥을 눌러 아무 일도 일어나지 않는다.
  //    → scrollIntoView로 끌어올린 뒤, elementFromPoint로 실제 클릭 대상인지 확인하고 클릭한다.
  let found: any = null;
  for (let attempt = 0; attempt < 12; attempt++) {
    found = await page.evaluate(`(() => {
      var t = ${JSON.stringify(target)};
      var norm = function (s) { return (s || '').replace(/\\s+/g, '').toLowerCase(); };
      var items = Array.prototype.slice.call(document.querySelectorAll('[role="menuitem"]'));
      var hit = null;
      for (var i = 0; i < items.length; i++) {
        if (norm(items[i].innerText).indexOf(t) !== -1) { hit = items[i]; break; }
      }
      if (!hit) return { ok: false, available: items.map(function (e) { return norm(e.innerText); }).filter(Boolean) };

      hit.scrollIntoView({ block: 'center' });
      var r = hit.getBoundingClientRect();
      var x = r.x + r.width / 2, y = r.y + r.height / 2;
      // 해당 좌표의 최상위 요소가 이 항목(또는 그 자손)인지 확인 — 클리핑/가림 방지
      var top = document.elementFromPoint(x, y);
      var clickable = !!(top && (hit === top || hit.contains(top)));
      return { ok: true, clickable: clickable, x: x, y: y, label: hit.innerText.replace(/\\s+/g, ' ').trim() };
    })()`);

    if (found.ok && found.clickable) break;

    // 아직 없거나 가려져 있으면 메뉴를 아래로 스크롤하고 재시도
    await page.mouse.move(900, 600);
    await page.mouse.wheel(0, 200);
    await page.waitForTimeout(400);
  }

  if (!found || !found.ok) {
    await page.keyboard.press('Escape').catch(() => {});
    throw new Error(
      `모델 "${targetModel}"을 메뉴에서 찾지 못했습니다.\n사용 가능한 항목: ${JSON.stringify(found?.available)}`
    );
  }
  if (!found.clickable) {
    await page.keyboard.press('Escape').catch(() => {});
    throw new Error(`모델 "${targetModel}" 항목이 가려져 클릭할 수 없습니다.`);
  }

  console.log(`메뉴 항목 발견: "${found.label}" → 클릭 (${Math.round(found.x)}, ${Math.round(found.y)})`);
  await page.mouse.click(found.x, found.y);
  await page.waitForTimeout(1800);

  // 3) 검증: 버튼 라벨이 목표 모델로 바뀌었는지 확인
  const after = await page.evaluate((sel: string) =>
    (document.querySelector(sel) as HTMLElement)?.innerText?.trim() || '', SEL.modelButton);

  if (!matches(norm(after), target)) {
    throw new Error(`모델 선택 검증 실패: 버튼이 여전히 "${after}" 입니다 (목표: "${targetModel}").`);
  }

  console.log(`✅ 모델 선택 검증 완료: "${after}"`);
  return after;
}
