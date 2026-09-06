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
sudo apt-get install --no-install-recommends xvfb x11vnc novnc websockify xdotool
```

(`google-chrome`은 기존 `url_to_pdf.sh`와 공용으로 사용)

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

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
