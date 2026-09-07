# headless-browser-with-ai

Linux 서버에서 AI를 활용할 때 ego lite, aside와 같은 방식으로 화면을 스크랩(scrap)하는
기능을 우선 제공하는 프로젝트입니다. AI 세션 없이 사람이 직접 실행/조작할 수 있는
두 가지 도구를 제공한다:

- `scripts/url_to_pdf.sh` — URL을 PDF/PNG로 정적 렌더링(로그인 불필요한 페이지용)
- `scripts/live_browser.sh` — noVNC로 실제 화면을 보며 로그인 등 직접 조작이 필요한
  페이지용 (로그인 세션은 프로필에 저장되어 유지됨, 여러 개 동시 실행 가능)

## URL → PDF/PNG 렌더링 (AI 개입 없이 사용)

`scripts/url_to_pdf.sh`는 로컬에 설치된 headless Chrome으로 URL을 그대로 렌더링해
PDF(및 선택적으로 PNG)로 저장한다. 사람이 URL만 넣고 직접 실행하거나 cron에 등록해
쓰는 용도로, 실행할 때마다 AI 세션이 필요하지 않다.

### 요구 사항

- `google-chrome` 또는 `chromium`/`chromium-browser` 실행 파일 (PATH에 있어야 함)
- (`--png` 옵션 사용 시) `poppler-utils`의 `pdftoppm`

### 사용법

```bash
./scripts/url_to_pdf.sh <URL> [output_dir] [--png]
```

| 인자 | 필수 여부 | 설명 |
| --- | --- | --- |
| `URL` | 필수 | 렌더링할 페이지 주소 (`http://` 또는 `https://` 포함) |
| `output_dir` | 선택, 기본값 `./output` | 결과 파일을 저장할 디렉터리 (없으면 자동 생성) |
| `--png` | 선택 | PDF 생성 후 페이지별 PNG(`-01.png`, `-02.png`, ...)도 함께 생성 |

### 예시

```bash
# 기본 output/ 디렉터리에 PDF만 생성
./scripts/url_to_pdf.sh "http://psncs.iptime.org/stock_candle/"

# 디렉터리를 지정하고 PNG도 함께 생성
./scripts/url_to_pdf.sh "http://psncs.iptime.org/stock_candle/" ./output --png

# cron 등록 예시 (매일 08:00에 스냅샷 저장)
0 8 * * * /path/to/headless-browser-with-ai/scripts/url_to_pdf.sh "http://psncs.iptime.org/stock_candle/" /path/to/output --png
```

### 출력

`output_dir`에 `<타임스탬프>_<URL슬러그>.pdf` 형식으로 저장되며(예:
`20260906_090000_psncs.iptime.org_stock_candle_.pdf`), `--png`를 주면 같은 접두사에
페이지 번호를 붙인 PNG(`..._-01.png`, `..._-02.png`, ...)도 함께 생성된다.

### 참고

- 페이지가 무겁거나(CDN 스크립트 로딩 등) 렌더링이 덜 된 채 저장된다면 스크립트
  내부의 `--virtual-time-budget`(기본 30000ms) 값을 늘린다.
- PNG 해상도를 바꾸려면 스크립트 내부 `pdftoppm -r 110`의 DPI 값을 조정한다
  (해상도를 높이면 파일 크기도 커진다).
- 이메일 발송 등 후속 처리는 포함되어 있지 않다. 필요하면 이 스크립트가 생성한
  PDF/PNG 파일을 별도 도구(msmtp, sendmail 등)로 이어서 처리하면 된다.

## 로그인 세션 유지 라이브 브라우저 (noVNC, AI 개입 없이 사람이 직접 로그인)

`scripts/live_browser.sh`는 실제로 화면이 그려지는 Chrome을 가상 디스플레이(Xvfb) 위에
띄우고, 그 화면을 noVNC로 감싸서 일반 웹 브라우저로 그대로 보고 마우스/키보드로
조작할 수 있게 한다. 로그인 페이지가 나오면 사람이 직접 noVNC 화면에서 아이디/비밀번호를
입력하면 되고, 그 로그인 세션(쿠키 등)은 Chrome 프로필 디렉터리에 저장되어 스크립트를
껐다 켜도 재로그인 없이 유지된다.

### 요구 사항

```bash
sudo apt-get update
sudo apt-get install --no-install-recommends xvfb x11vnc novnc websockify xdotool
```

(`google-chrome`은 기존 `url_to_pdf.sh`와 공용으로 사용)

`google-chrome`/`google-chrome-stable`은 배포판 기본 apt 저장소에 없는 경우가
많다(구글 apt 저장소를 별도로 추가하지 않은 시스템). 이럴 때는 공식 `.deb`를
받아서 설치한다(의존 패키지는 `apt-get install`이 자동으로 해결한다):

```bash
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt-get install -y ./google-chrome-stable_current_amd64.deb
```

`which google-chrome`으로 설치가 됐는지 먼저 확인하고, 없을 때만 위 과정을 진행하면 된다.

### sudo 권한이 없는 환경(devcontainer 등)에서 실행하는 경우

이 프로젝트를 만들 때 실제로 겪은 상황: 작업 중이던 컨테이너/서버에는 `Xvfb`
자체가 설치돼 있지 않았고(`Xvfb: command not found`), 그 환경에는 sudo 비밀번호도
없어 패키지를 설치할 수 없었다. 이런 경우 해결 방법은 두 가지다.

1. **sudo가 되는 다른 서버에 리포지토리를 clone해서 거기서 실행한다.**
   ```bash
   ssh <sudo가-되는-서버>
   git clone https://github.com/cheoljoo/headless-browser-with-ai.git ~/code/headless-browser-with-ai
   cd ~/code/headless-browser-with-ai
   sudo apt-get update
   sudo apt-get install --no-install-recommends -y xvfb x11vnc novnc websockify
   # google-chrome이 없다면 위 "요구 사항" 절의 .deb 설치 과정을 그대로 진행
   ./scripts/live_browser.sh start "<URL>" <SESSION>
   ```
   noVNC 접속 주소(`http://<그 서버 IP>:<WEB_PORT>/vnc.html`)는 그 서버 기준으로
   출력되므로, 원래 작업 중이던 환경이 아니라 이 서버의 IP로 접속해야 한다.
2. 애초에 sudo/패키지 설치가 가능한 환경에서 개발/실행한다.

`apt-cache policy xvfb x11vnc novnc websockify python3-websockify`로 각 패키지가
해당 배포판 저장소에 있는지 먼저 확인해보면(Ubuntu 계열은 대부분 기본 universe/main
저장소에 존재) 설치 가능 여부를 빠르게 파악할 수 있다.

### 사용법

```bash
./scripts/live_browser.sh start [URL] [SESSION]   # 세션 시작 (SESSION 기본값: default)
./scripts/live_browser.sh status [SESSION]        # 특정 세션 상태 확인
./scripts/live_browser.sh stop [SESSION]          # 세션 종료
./scripts/live_browser.sh list                    # 실행 중인 모든 세션과 접속 주소 목록
```

시작하면 그 세션에 할당된 주소가 출력된다. 그 주소를 아무 브라우저에서나 열어
화면을 보며 로그인 등을 직접 진행한다:

```
http://<이 서버의 IP>:<세션별 WEB_PORT>/vnc.html
```

### 여러 개 동시에 띄우기 (세션별로 별도 포트)

`SESSION` 이름을 다르게 주면 여러 개를 동시에 띄울 수 있고, 각 세션은 서로 겹치지
않는 Xvfb 디스플레이 번호·VNC 포트·noVNC 웹 포트·Chrome 프로필을 **자동으로**
할당받는다. 즉 한 번에 여러 창(예: 여러 사이트, 또는 여러 작업)을 동시에 열어도
세션마다 별도의 웹 포트(주소)로 개별 접속/조작할 수 있다.

```bash
./scripts/live_browser.sh start "http://siteA.example.com" siteA
./scripts/live_browser.sh start "http://siteB.example.com" siteB

./scripts/live_browser.sh list
# siteA: http://<서버 IP>:6080/vnc.html (VNC 5900, DISPLAY 99)
# siteB: http://<서버 IP>:6081/vnc.html (VNC 5901, DISPLAY 100)
```

### 예시

```bash
# 로그인 페이지가 있는 사이트를 열어 직접 로그인 (세션 이름 생략 시 "default")
./scripts/live_browser.sh start "http://psncs.iptime.org/todo/"

# 상태 확인 / 종료
./scripts/live_browser.sh status
./scripts/live_browser.sh stop

# 다시 시작해도 이전에 로그인한 세션이 그대로 유지된다
./scripts/live_browser.sh start "http://psncs.iptime.org/todo/"
```

### 환경변수

기본적으로 아래 값들은 세션마다 자동으로 겹치지 않게 할당되므로 직접 지정할
필요가 없다. 특정 값을 강제로 고정하고 싶을 때만 지정한다(그 경우 자동 할당은
건너뛴다).

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `DISPLAY_NUM` | 자동 할당(99부터) | Xvfb 디스플레이 번호 |
| `SCREEN_SIZE` | `1600x900x24` | 가상 화면 해상도 |
| `VNC_PORT` | 자동 할당(5900부터) | x11vnc가 듣는 VNC 포트 |
| `WEB_PORT` | 자동 할당(6080부터) | noVNC 웹 포트 (브라우저로 접속하는 포트) |
| `PROFILE_DIR` | `<repo>/live_profile/<SESSION>` | 로그인 세션(쿠키 등)이 저장되는 Chrome 프로필 경로 |
| `VNC_PASSWORD` | (없음) | 지정하면 noVNC 접속 시 비밀번호를 요구한다 |

### 보안 참고

- `VNC_PASSWORD`를 지정하지 않으면 `WEB_PORT`(기본 6080)에 접근 가능한 누구나
  인증 없이 화면을 보고 조작할 수 있다. 외부에서 접근 가능한 네트워크라면
  반드시 `VNC_PASSWORD`를 설정하거나 방화벽으로 접근을 제한할 것.
- `live_profile/`에는 로그인 쿠키 등 민감 정보가 그대로 저장되므로 git에 커밋하지
  않는다(`.gitignore`에 이미 등록되어 있음).

### 구현 참고 (다중 세션 포트 할당)

세션 시작 시 Xvfb 디스플레이/VNC 포트/noVNC 웹 포트가 비어 있는지 확인한 뒤 그
값으로 각 프로세스를 띄우는데, 시스템 부하가 높으면 "확인 시점"과 "실제 바인딩
시점" 사이에 경쟁 상태(race condition)가 생겨 두 세션이 같은 포트를 고르는
문제가 있었다. 그래서 각 프로세스를 띄운 뒤 고정 `sleep` 대신 해당 포트/디스플레이가
실제로 열릴 때까지 최대 5초간 폴링(`wait_port_listening`, `wait_display_ready`)하고,
그래도 안 열리면 그 자리에서 에러로 중단하도록 만들었다(포트 재사용으로 인한 조용한
실패 대신 명확한 실패).

### 동작 확인 사례

- `http://psncs.iptime.org/todo/`에서 비밀번호 `2222`를 noVNC 화면에서 직접 입력해
  "읽기전용(readonly)" 권한으로 로그인되는 것과, `stop` 후 `start`로 재시작해도
  재로그인 없이 세션이 그대로 유지되는 것을 확인했다.
- 서로 다른 URL로 세션 두 개(`siteA`, `siteB`)를 동시에 띄워 각각 6080/6081
  포트로 독립적으로 접속·렌더링되는 것을 확인했다.

## 사용례: AI가 noVNC로 화면을 조작하며 정보를 수집해 메일로 보고하기

`live_browser.sh`로 띄운 화면은 사람만 조작하는 게 아니라, 같은 서버에서
`xdotool`(클릭/키 입력)과 `import`(ImageMagick, 스크린샷)를 조합하면 AI 세션도
그 화면을 보고 조작할 수 있다. 아래는 실제로 주고받은 프롬프트와 그 결과를
정리한 것으로, 비슷한 작업을 시킬 때 참고할 수 있다.

### 1) "화면 보고 확인해줘" → 스크린샷으로 상태 확인

> 프롬프트: *"지금 제가 passwd 입력했습니다. 이것을 이어서 하므로 해당 session
> 관련하여 내용을 볼수 있는지 확인해주세요."*

AI가 한 일: 원격 서버에 `imagemagick`(`import`)이 없어 `apt-get install`로 설치한
뒤, `DISPLAY=:99 import -window root shot.png`로 현재 화면을 캡처해 로컬로
`scp`로 가져와 Read 도구로 확인. 결과를 사람이 알아볼 수 있게 "현재 로그인 상태,
어떤 화면이 떠 있는지"로 요약해서 답변.

### 2) "클릭해서 뭔가 해줘" → xdotool로 원격 조작

> 프롬프트: *"이 화면에서 뭔가를 누르고 하는 행동을 할수 있나요?"* →
> *"할수 있다면 로그아웃을 하고 다시 login을 해서 passwd는 222로 입력해주세요."*

AI가 한 일: `xdotool`을 원격 서버에 설치한 뒤, 스크린샷 위에 좌표를 겹쳐 그려
버튼 위치를 정확히 찾고(`convert ... -draw "line ..."`), `mousemove`+`click`으로
버튼을 눌러봄. 이 과정에서 로그인 폼이 약 1초 만에 자동 새로고침되어 닫혀버리는
것과, 입력창이 이전 시도의 문자를 제대로 지우지 못하는 문제를 발견 — 여러 번
재시도했지만 "222"만 정확히 넣는 데는 실패했고, 그 사실과 원인을 숨기지 않고
그대로 보고한 뒤 noVNC로 사람이 직접 하길 권함. **자동화가 항상 성공하는 건
아니며, 실패했을 때 무엇을 시도했고 왜 안 됐는지 구체적으로 보고하는 것이
중요하다는 걸 보여주는 사례.**

### 3) "다른 사이트 열어서 눌러보고 요약해줘" → 여러 화면 탐색 + 요약

> 프롬프트: *"http://psncs.iptime.org/stock_index/ 을 접속해주세요. 그리고, 그
> 안의 것들을 눌러서 나오는 정보들을 요약해주세요."*

AI가 한 일: 이미 떠 있던 Chrome 창의 주소창을 `xdotool key ctrl+l` +
`xdotool type`으로 바꿔 새 URL로 이동한 뒤, 좌측 메뉴 항목들을 하나씩 클릭하고
(`xdotool mousemove X Y click 1`) 매번 스크린샷을 찍어 로딩이 끝났는지 확인하며
9개 화면(대시보드, 데드캣 바운스 분석, 상승 추세 전환 분석, 반도체 산업 분석,
ROIC 분석, 미국 물가·환율, 외국인·기관 수급 스크리너 등)을 순서대로 탐색. 각
화면의 수치와 결론 텍스트를 읽어 한국어로 요약 정리.

### 4) "본 화면들을 html로 정리해서 메일로 보내줘"

> 프롬프트: *"이때 이동하면서 본 화면들의 내용에 대해서 html에 뭐를 봤을때 png
> 무슨 내용이었고 그 내용에 대한 해설이 무엇이라고 적어주고, 이것을 email로
> cheoljoo.lee@lge.com 으로 보내주세요."*

처음에는 Gmail API(MCP)로 캡처한 PNG를 base64로 인코딩해 인라인 첨부하려
했으나, base64 문자열(수만 자)이 AI 응답 토큰 제한에 걸려 잘리거나 손상되는
문제가 있었다. 이어진 프롬프트로 방향을 바꿈:

> 프롬프트: *"ai로 들어가서 페이지 png를 받아두고 뭐라고 설명을 달지를 json에
> 만들어두고, 이 json과 png 을 읽어서 메일로 보내는 것은 script를 만들면
> 어떨까해. 회사 내부적으로는 ../ccr/sendmail.py 를 copy해서 변경해서 쓰면 될
> 것으로 보입니다."*

AI가 한 일: 기존 `~/code/ccr/sendmail.py`(사내 SMTP 릴레이로 메일 발송하는
스크립트)를 참고해 `scripts/send_screenshot_report.py`를 새로 작성. 캡처
이미지 경로와 "본 것/해설"을 담은 JSON 매니페스트를 별도로 만든 뒤, 스크립트가
그 JSON을 읽어 이미지를 **디스크에서 직접** MIME 메시지에 첨부해 발송하도록
했다. **AI의 응답 토큰을 거치지 않고 이미지를 다루므로 base64 손상 문제 자체가
발생하지 않는다** — 사람이 눈으로 보고 판단해야 하는 대용량 바이너리(이미지,
첨부파일 등)를 다룰 때는, 그걸 대화 토큰으로 옮겨 담으려 하지 말고 이렇게
스크립트가 파일시스템에서 직접 읽어 처리하게 하는 편이 훨씬 안전하고 빠르다.

### `scripts/send_screenshot_report.py` 사용법

```bash
./scripts/send_screenshot_report.py \
  --manifest report.json \
  --to someone@lge.com \
  --subject "제목" \
  [--sender cheoljoo.lee@lge.com] [--test]
```

`report.json` 형식:

```json
{
  "intro": "리포트 맨 위에 들어갈 소개 문구(선택)",
  "items": [
    {"image": "/절대/경로/screenshot1.png", "title": "화면 제목",
     "seen": "무엇을 눌러서 나온 화면인지", "desc": "그 내용에 대한 해설"}
  ]
}
```

사내망 SMTP 릴레이(`lgekrhqmh01.lge.com:25`, 인증 불필요)로 발송하므로 사내
네트워크에서만 동작한다. `--test`를 주면 실제 발송 없이 몇 장을 어떤 제목으로
보낼지만 출력한다.

## 참고: 유사 아키텍처와 개선 아이디어

이 프로젝트가 택한 방식(Xvfb + x11vnc + noVNC + Chrome, 하나의 화면을 사람과
AI가 함께 봄)은 "사람-AI 협업 브라우징"을 구현하는 여러 방법 중 하나다. 실제로
`live_browser.sh`에 대해 AI 에이전트가 `xdotool`로 화면을 조작해보니(위
"동작 확인 사례" 참고), **좌표만 보고 눈먼 클릭을 하다 보니 폼이 열렸는지
닫혔는지조차 스크린샷을 찍어봐야 알 수 있었고, 어떤 사이트는 1초 안에 자동
새로고침되어 그 틈을 맞추기 어려웠다.** 이 한계와 대안을 정리해둔다.

### CDP(원격 디버깅 포트)를 병행하면 더 정확해진다

**CDP(Chrome DevTools Protocol)** 란 Chrome/Chromium이 노출하는 JSON-RPC 기반
원격 제어 프로토콜로, `--remote-debugging-port`로 브라우저를 띄우면 외부
프로그램이 WebSocket으로 접속해 DOM 조회, JS 실행, 클릭/타이핑 이벤트 주입,
네트워크 가로채기, 스크린샷/PDF 캡처 등을 할 수 있다. 크롬 개발자도구(F12)가
화면에서 하는 일을 코드로 그대로 할 수 있게 해주는 것이라고 보면 된다.
Puppeteer, Playwright(Chromium 드라이버), 그리고 아래에서 이야기할
Browserless/Steel 모두 이 CDP 위에서 동작한다.

지금 `live_browser.sh`가 띄우는 Chrome에 `--remote-debugging-port=9222`
옵션만 추가하면, AI는 noVNC 화면을 눈으로 보며 좌표를 추측해 클릭하는 대신
**CDP(Chrome DevTools Protocol)로 DOM을 직접 조회하고, 특정 엘리먼트가 실제로
클릭 가능한 상태인지 확인한 뒤 JS로 값을 넣거나 클릭 이벤트를 보낼 수 있다.**
같은 화면을 사람은 noVNC로 보면서 필요할 때(2FA, 캡차, 결제 승인 등) 직접
마우스/키보드로 개입하고, AI는 CDP로 정밀하게 조작하는 두 채널을 병행하는
구조다. 이번에 `xdotool` 눈먼 클릭이 실패했던 사례(비밀번호 입력 폼이
자동 리셋되기 전에 클릭+입력을 못 맞춤)는 CDP를 썼다면 DOM 상태를 직접
확인·조작할 수 있어 훨씬 안정적이었을 것이다. 다음에 이런 자동 조작이 필요하면
`--remote-debugging-port` 추가와 Playwright/Puppeteer 연결을 우선 검토할 것.

### 사람과 AI가 화면을 나눠 써야 한다면: 디스플레이 분리(멀티스페이스)

지금 구조는 사람과 AI가 **같은 마우스 커서, 같은 화면**을 공유한다(동시에
조작하면 커서가 서로 충돌한다). 만약 AI는 백그라운드에서 계속 작업하고,
사람은 필요할 때만 잠깐 들여다보는 식으로 완전히 분리하고 싶다면, 같은 Chrome
프로필(쿠키 등)을 서로 다른 `DISPLAY` 번호(예: 사람용 `:1`, AI 전용 `:99`)에서
각각 띄우는 방법이 있다. AI가 2FA 등 사람 개입이 필요하다고 판단하면 알림을
보내고, 그때만 `:99` 화면을 noVNC로 열어보게 하는 식이다. 지금 `live_browser.sh`는
세션마다 디스플레이를 자동 할당하므로(README 위쪽 "여러 개 동시에 띄우기"
참고), 같은 프로필 디렉터리를 두 세션에서 공유하도록 `PROFILE_DIR`를 맞춰주면
비슷하게 흉내 낼 수 있다.

### 헤드리스에서도 화면이 "제대로" 그려지는 이유

`live_browser.sh`는 실제 화면(Xvfb)을 띄우지만, 완전히 헤드리스로 돌리는
`url_to_pdf.sh`도 스크린샷/PDF가 깨지지 않고 나온다. 이는 브라우저의 렌더링
파이프라인(레이아웃→페인트→래스터화)이 "모니터에 빛을 쏘는 단계(Scanout)"
직전, 즉 **메모리 버퍼에 픽셀을 채우는 단계까지는 실제 디스플레이 장치 유무와
무관하게 항상 수행되기 때문**이다(GPU가 없으면 SwiftShader/Mesa llvmpipe 같은
소프트웨어 래스터라이저가 대신 계산한다). 반대로 말하면, `--virtual-time-budget`
을 늘려도 페이지가 여전히 깨져 보인다면 레이아웃 자체가 안 끝난 게 아니라
지연 로딩(`IntersectionObserver`, 스크롤 기반 로딩) 때문에 필요한 네트워크
요청이 아직 트리거되지 않았을 가능성을 먼저 의심해볼 것.

### 비슷한 목적의 기존 오픈소스 스택

바닥부터 셸 스크립트로 구성하는 대신 쓸 수 있는 패키징된 대안들:

- **[Browserless](https://www.browserless.io/)** — 웹사이트/소개.
  self-host용 오픈소스 코드는 [github.com/browserless/browserless](https://github.com/browserless/browserless).
  Docker 컨테이너 하나로 Headless Chrome + CDP 디버거 + 사람이 마우스로 개입할
  수 있는 Live Debugger UI를 한 번에 제공. 오픈소스판과 별도로 상용
  클라우드/엔터프라이즈 티어도 운영한다.
- **[Steel](https://steel.dev/)** — 웹사이트/소개("open source browser API
  that lets you control fleets of browsers in the cloud"). self-host용
  코드는 [github.com/steel-dev/steel-browser](https://github.com/steel-dev/steel-browser)
  (Python SDK: [steel-dev/steel-python](https://github.com/steel-dev/steel-python),
  예제: [steel-dev/steel-cookbook](https://github.com/steel-dev/steel-cookbook)).
  세션 유지, 프록시, 쿠키 관리, 자동 CAPTCHA 해결과 함께 사람이 언제든 볼 수
  있는 Live View Session을 내장한, 처음부터 **AI 에이전트용**으로 설계된
  오픈소스 브라우저 인프라.

두 도구를 비교하면:

| 기준 | Browserless | Steel |
| --- | --- | --- |
| 태생 | 헤드리스 크롬을 스케일 있게 돌리기(스크래핑/PDF 대량생산)에서 출발 | 처음부터 "AI 에이전트용 브라우저 인프라"로 설계 |
| Live View(사람 개입) | 있지만 부가 기능에 가까움 | 세션 지속성·프록시·쿠키 관리와 함께 핵심 기능으로 다뤄짐 |
| 라이선스/운영 모델 | 오픈소스 버전 + 상용 클라우드/엔터프라이즈 티어 병행 | 완전 오픈소스, self-host 전제로 설계되어 별도 계정/API 키 없이도 온전히 동작 |
| 이 리포지토리와의 궁합 | `url_to_pdf.sh`처럼 대량 스크린샷/PDF 생성을 스케일업할 때 강점 | `live_browser.sh`가 하려는 "로그인 세션 유지 + 사람 개입" 워크플로우와 사상이 거의 동일 |

**둘 중 고른다면 Steel을 추천한다.** Browserless는 "많이, 빠르게 헤드리스로
돌리기"에 최적화된 반면, Steel은 "세션을 유지하면서 사람이 언제든 들여다볼 수
있게 하기"에 최적화되어 있는데, `live_browser.sh`가 풀려는 문제가 정확히
후자이기 때문이다. 사내망처럼 외부 SaaS 계정 연동이 부담스러운 폐쇄망
환경에서도 Steel은 순수 self-host로 완결되어 있어, 지금 구조(Xvfb+noVNC를
직접 짠 것)를 컨테이너 하나로 대체하는 그림이 자연스럽다. 다만 두 프로젝트
다 변화가 빠른 오픈소스라 실제 도입 전에는 각 저장소에서 최신 라이선스/기능
구성을 다시 확인할 것.

이 리포지토리는 위 도구들을 쓰지 않고 `xvfb`/`x11vnc`/`novnc`만으로 최소
구성한 버전이라고 보면 된다. 사내망 등 외부 이미지를 끌어올 수 없는 환경이거나
가볍게 셸 스크립트로만 관리하고 싶을 때 적합하고, 세션 관리/프록시/멀티유저
같은 기능이 필요해지면 위 도구로 옮겨가는 걸 고려할 만하다.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
