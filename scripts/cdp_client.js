#!/usr/bin/env node
// 최소 CDP(Chrome DevTools Protocol) 클라이언트. steel_browser.sh(또는 --remote-debugging-port로
// 띄운 아무 Chrome/Chromium)의 CDP WebSocket에 붙어 화면을 스크린샷 없이 "텍스트로" 조작·크롤링한다.
//
// 사용법: node cdp_client.js <wsUrl> <command> [json-params]
//
// 명령:
//   evaluate  {"expression": "JS 코드"}                — JS를 실행하고 반환값을 출력 (크롤링의 핵심)
//   click     {"selector": "CSS selector"}             — querySelector로 찾은 엘리먼트를 클릭
//   navigate  {"url": "https://..."}                   — 현재 탭을 그 URL로 이동
//   screenshot                                          — PNG를 base64로 stdout에 출력
//   login     {"userSelector":"#id","passSelector":"#pw"} — CDP_LOGIN_ID/CDP_LOGIN_PASSWORD 환경변수
//             값을 두 입력창에 채운다(비밀번호가 인자/로그에 남지 않도록 반드시 env로만 전달할 것)
//
// 필요한 것: npm install ws  (이 파일과 같은 디렉터리에서)
const WebSocket = require('ws');

const [, , wsUrl, cmd, paramsJson] = process.argv;
const params = paramsJson ? JSON.parse(paramsJson) : {};

const ws = new WebSocket(wsUrl, { maxPayload: 50 * 1024 * 1024 });
let id = 1;
function send(method, sendParams) {
  return new Promise((resolve, reject) => {
    const msgId = id++;
    const handler = (data) => {
      const msg = JSON.parse(data);
      if (msg.id === msgId) {
        ws.off('message', handler);
        if (msg.error) reject(new Error(JSON.stringify(msg.error)));
        else resolve(msg.result);
      }
    };
    ws.on('message', handler);
    ws.send(JSON.stringify({ id: msgId, method, params: sendParams }));
  });
}

ws.on('open', async () => {
  try {
    if (cmd === 'evaluate') {
      const r = await send('Runtime.evaluate', {
        expression: params.expression,
        returnByValue: true,
        awaitPromise: true,
      });
      console.log(JSON.stringify(r.result));
    } else if (cmd === 'screenshot') {
      const r = await send('Page.captureScreenshot', { format: 'png' });
      process.stdout.write(r.data);
    } else if (cmd === 'navigate') {
      const r = await send('Page.navigate', { url: params.url });
      console.log(JSON.stringify(r));
    } else if (cmd === 'click') {
      const expr = `(function(){ const el = document.querySelector(${JSON.stringify(
        params.selector
      )}); if(!el) return 'NOT_FOUND'; el.click(); return 'CLICKED'; })()`;
      const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true });
      console.log(JSON.stringify(r.result));
    } else if (cmd === 'login') {
      // 자격증명은 env로만 받는다 — argv나 이 스크립트 호출 로그에 절대 남기지 않기 위함.
      const userId = process.env.CDP_LOGIN_ID || '';
      const password = process.env.CDP_LOGIN_PASSWORD || '';
      const expr = `
        (function(){
          const u = document.querySelector(${JSON.stringify(params.userSelector)});
          const p = document.querySelector(${JSON.stringify(params.passSelector)});
          if(!u || !p) return 'FIELDS_NOT_FOUND';
          u.value = ${JSON.stringify(userId)};
          u.dispatchEvent(new Event('input', {bubbles:true}));
          u.dispatchEvent(new Event('change', {bubbles:true}));
          p.value = ${JSON.stringify(password)};
          p.dispatchEvent(new Event('input', {bubbles:true}));
          p.dispatchEvent(new Event('change', {bubbles:true}));
          return 'FILLED';
        })()`;
      const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true });
      console.log(JSON.stringify(r.result));
    } else {
      console.error('unknown cmd:', cmd, '(evaluate|screenshot|navigate|click|login)');
      process.exit(1);
    }
  } catch (e) {
    console.error('ERROR', e.message);
    process.exit(1);
  } finally {
    ws.close();
  }
});
ws.on('error', (e) => {
  console.error('WS ERROR', e.message);
  process.exit(1);
});
