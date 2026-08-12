/**
 * 브라우저를 한 번만 띄운 채로:
 *   1) 로그인 확인
 *   2) 모델 드롭다운을 열어 지금 고를 수 있는 모델 목록을 stdout에 출력
 *   3) answerFile(JSON: {"model": "..."})이 나타날 때까지 "브라우저를 닫지 않고" 대기
 *   4) 파일이 나타나면 그 모델로 즉시 선택 → 프롬프트 입력 → 전송 → 응답/아티팩트 추출
 *
 * listModels.ts + executor.ts를 따로 실행하면 브라우저를 두 번 열고 닫게 되는데,
 * 그러면 세션/탭 상태가 리셋되고 매번 페이지 로딩을 기다려야 한다. 이 스크립트는
 * 하나의 브라우저 세션을 계속 띄워둔 채로 "목록 조회 → (사람 선택 대기) → 즉시 진행"까지
 * 이어가기 위한 것이다.
 *
 *   npx tsx interactive.ts "<프롬프트 또는 @파일경로>" [answerFile] [이미지경로]
 *
 * 사용하는 쪽(에이전트)의 절차:
 *   1. 이 스크립트를 백그라운드로 실행
 *   2. stdout에서 "MODELS_JSON:[...]" 줄이 나올 때까지 출력 확인
 *   3. 사용자에게 실제 선택 UI(AskUserQuestion 등)로 모델을 고르게 함
 *   4. 고른 모델명을 answerFile에 {"model": "<라벨>"} 로 기록
 *   5. 스크립트가 이어서 완료할 때까지 대기 (완료 시 last_result.txt 등 저장)
 */
import { chromium } from 'playwright';
import fs from 'fs';
import { ensureLoggedIn } from './session.js';
import { SEL, listAvailableModels } from './notionUi.js';
import { runPrompt } from './executor.js';

const PROFILE_DIR = 'C:/Users/nam9n/.claude/skills/notionAI/notion_chrome_profile';

async function main() {
  const rawArg = process.argv[2] || '안녕하세요! 간단한 테스트입니다.';
  const prompt = rawArg.startsWith('@') ? fs.readFileSync(rawArg.slice(1), 'utf8') : rawArg;
  const answerFile = process.argv[3] || 'model_choice.json';
  const imagePath = process.argv[4] || '';
  const waitTimeoutMs = 10 * 60 * 1000; // 사람이 고를 시간 — 최대 10분

  // 이전 실행이 남긴 답변 파일이 있으면 곧바로 그걸 집어먹지 않도록 미리 지운다.
  try { fs.unlinkSync(answerFile); } catch { /* 없으면 무시 */ }

  const browser = await chromium.launchPersistentContext(PROFILE_DIR, {
    headless: false,
    viewport: { width: 1280, height: 900 },
  });
  const page = browser.pages()[0] || await browser.newPage();
  await page.addInitScript({ content: 'globalThis.__name = globalThis.__name || ((f) => f);' });
  await page.evaluate('globalThis.__name = globalThis.__name || ((f) => f)').catch(() => {});

  try {
    console.log('Notion AI 페이지로 이동...');
    await ensureLoggedIn(page, { headless: false });
    await page.waitForSelector(SEL.modelButton, { timeout: 20000 });

    console.log('모델 목록 조회 중...');
    const models = await listAvailableModels(page);
    if (models.length === 0) throw new Error('모델 메뉴에서 항목을 하나도 찾지 못했습니다.');
    console.log('MODELS_JSON:' + JSON.stringify(models));
    console.log(`브라우저를 열어둔 채 모델 선택을 기다립니다 (최대 ${Math.round(waitTimeoutMs / 60000)}분). ` +
      `${answerFile} 파일에 {"model":"<선택한 라벨>"} 을 쓰면 바로 이어서 진행합니다.`);

    const start = Date.now();
    let chosenModel = '';
    while (Date.now() - start < waitTimeoutMs) {
      if (fs.existsSync(answerFile)) {
        try {
          const parsed = JSON.parse(fs.readFileSync(answerFile, 'utf8'));
          if (parsed && parsed.model) {
            chosenModel = parsed.model;
            fs.unlinkSync(answerFile);
            break;
          }
        } catch {
          // 쓰는 도중에 읽었을 수 있다 — 다음 루프에서 재시도
        }
      }
      if (page.isClosed()) throw new Error('대기 중 브라우저가 닫혔습니다.');
      await page.waitForTimeout(1000);
    }

    if (!chosenModel) {
      throw new Error(`모델 선택 대기 시간이 초과되었습니다 (${answerFile} 파일이 오지 않음).`);
    }

    console.log(`모델 선택됨: "${chosenModel}" → 바로 진행`);
    const result = await runPrompt(page, browser, prompt, { model: chosenModel, imagePath });

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
  } finally {
    await browser.close().catch(() => {});
  }
}

main().catch(err => {
  console.error('\n❌ 실패:', err.message);
  process.exit(1);
});
