---
name: steel-cdp-browse
description: >
  self-host Steel(Docker) 브라우저 컨테이너를 띄우고 CDP(Chrome DevTools Protocol)로 직접
  DOM을 조회·클릭·입력해 웹사이트를 탐색/크롤링/로그인하는 방법. "이 사이트 열어서 정보
  긁어와줘", "steel/CDP로 로그인해줘", "브라우저 조작하면서 결과를 볼 수 있게 해줘" 같은
  요청에 쓴다. xdotool+스크린샷 방식(좌표 기반 클릭, 화면을 vision으로 해석)보다 훨씬
  정확하고 빠르다 — DOM 텍스트를 직접 읽으므로 화면을 "보고 추측"할 필요가 없다. 사람이
  동시에 웹 브라우저로 진행 상황을 볼 수 있는 Live View도 함께 제공한다. `make skill-install`로
  `~/.claude/skills/`에 설치되어 어느 프로젝트/디렉터리에서든 호출할 수 있다.
user-invocable: true
---

# Steel(Docker) + CDP 브라우징

사람이 필요하면 개입할 수 있는 Live View를 유지하면서, AI는 CDP로 DOM을 직접 읽고 조작해
웹사이트를 탐색/크롤링/로그인하는 절차. `headless-browser-with-ai` 리포지토리(
https://github.com/cheoljoo/headless-browser-with-ai )의 `scripts/steel_browser.sh`와
`scripts/cdp_client.js`를 사용한다.

이 skill은 `~/.claude/skills/steel-cdp-browse/`에 설치되어 **어느 디렉터리에서 호출되든**
동작해야 하므로, 0단계에서 실제 스크립트가 있는 리포지토리 위치부터 확보한다 — 지금 작업
디렉터리가 그 리포지토리라고 가정하지 말 것.

## 0. 준비 확인 — 리포지토리 위치 확보 + 의존성 체크

**순서대로 확인하고, 앞 단계에서 이미 찾았으면 뒤 단계는 건너뛴다.**

```bash
# (a) 지금 작업 디렉터리 자체가 이 리포지토리인가?
[ -f scripts/steel_browser.sh ] && REPO_DIR="$PWD"

# (b) 아니면 흔한 위치들을 확인한다 (사용자마다 clone 위치가 다를 수 있으므로 넓게 찾아본다)
if [ -z "$REPO_DIR" ]; then
  for d in "$HOME/code/headless-browser-with-ai" "$HOME/headless-browser-with-ai" \
           "$(find "$HOME/code" "$HOME" -maxdepth 3 -type d -name headless-browser-with-ai 2>/dev/null | head -1)"; do
    [ -n "$d" ] && [ -f "$d/scripts/steel_browser.sh" ] && { REPO_DIR="$d"; break; }
  done
fi

# (c) 그래도 못 찾았으면 clone한다 (어디에 둘지 애매하면 ~/code/ 아래를 기본으로 쓰되, 사내망이라
#     github.com 접근이 막혀 있으면 사용자에게 내부 미러 주소를 물어본다)
if [ -z "$REPO_DIR" ]; then
  mkdir -p "$HOME/code"
  git clone https://github.com/cheoljoo/headless-browser-with-ai.git "$HOME/code/headless-browser-with-ai" \
    && REPO_DIR="$HOME/code/headless-browser-with-ai"
fi

echo "REPO_DIR=$REPO_DIR"
```

`REPO_DIR`을 못 구했으면(clone도 실패) 사용자에게 리포지토리 위치를 물어보고 **여기서 멈춘다**
(추측한 경로로 계속 진행하지 말 것).

```bash
# Docker 확인 — 없으면 이 방법 자체가 불가능하니 바로 사용자에게 알리고 대안(live_browser.sh,
# Xvfb+xdotool 기반)을 제안한다.
which docker >/dev/null || { echo "Docker 없음 — steel-cdp-browse 사용 불가. live_browser.sh 대안 검토"; exit 1; }
docker info >/dev/null 2>&1 || echo "⚠ Docker 데몬에 접근 안 됨 (권한/미실행 확인 필요)"

# node/npm 확인
which node >/dev/null || { echo "Node.js 없음 — cdp_client.js 실행 불가"; exit 1; }

# cdp_client.js 의존성(ws 패키지) 설치 여부 확인 — 처음 clone/설치 직후엔 없을 수 있다
cd "$REPO_DIR/scripts"
[ -d node_modules/ws ] || npm install --no-audit --no-fund
```

## 1. 세션 시작 — **그리고 곧바로 Live View 주소부터 사용자에게 보여줄 것**

```bash
cd "$REPO_DIR"
./scripts/steel_browser.sh start "<시작 URL>" <세션이름>
```

⚠️ **다른 어떤 작업(CDP 타겟 찾기, 클릭, 텍스트 추출 등)보다 먼저**, 세션 시작 출력에 나오는
**Live View 주소(`http://<서버IP>:<API_PORT>/v1/sessions/debug`)를 사용자에게 바로 보여준다.**
사용자가 실시간으로 지켜보거나 필요할 때(2FA, 캡차 등) 직접 개입할 수 있어야 하므로, "이제부터
이 주소를 웹 브라우저로 열어서 보실 수 있습니다"라고 먼저 알린 뒤에 실제 크롤링/조작을 진행한다.
Dashboard(`/ui`)와 CDP endpoint(`http://<서버IP>:<CDP_PORT>`) 주소도 참고용으로 함께 안내한다.

세션 이름을 다르게 주면 여러 개 동시 실행 가능(포트 자동 할당). 이미 쓰던 세션이 있으면
`docker ps --filter name=steel-browser-` 로 확인하고 재사용해도 된다.

⚠️ **Live View가 원격(다른 PC)에서 "Session Offline"으로 뜬다면 — Docker
포트포워딩 문제가 아니라 `DOMAIN` 미설정 문제다.** steel-browser는 `HOST` 환경변수를
안 주면 기본값 `0.0.0.0`으로 자기 주소를 알고, Live View 페이지 HTML에
`ws://0.0.0.0:<PORT>/...`를 그대로 박아 넣는다. 그 페이지를 보는 브라우저는
`0.0.0.0`을 "자기 자신의 PC"로 해석하므로, 같은 서버 로컬에서는 우연히 되더라도 다른
PC(Windows 등)에서 열면 반드시 실패한다. CDP/REST API 자체(`curl`, `cdp_client.js`)는
포트포워딩만으로 계속 잘 되기 때문에 "포트가 막혔나?"로 착각하기 쉽지만 아니다.
`steel_browser.sh`는 이미 `-e DOMAIN=<서버IP>:<API_PORT>`를 자동으로 넣어 이 문제를 막아준다
(그 스크립트를 안 쓰고 `docker run`을 직접 짠다면 반드시 `DOMAIN` env를 넣을 것). 확인법:
`curl http://<서버IP>:<PORT>/v1/sessions/debug | grep baseWsUrl`로 `0.0.0.0`이 아니라 실제
IP가 박혀 있는지 볼 것.

세션을 새로 만들었는데 처음 페이지가 `about:blank`라면(예: 컨테이너 재시작 후 API로 세션만
다시 만든 경우) 2~3단계로 넘어가 `navigate` 명령으로 원하는 URL로 이동시키면 된다 — 사용자가
Live View로 지켜보고 있다면 이 이동 자체가 "동작하는 모습을 보여주는" 좋은 확인 포인트다.

## 2. CDP 타겟 찾기

```bash
curl -s http://localhost:<CDP_PORT>/json/list | python3 -m json.tool
```

`type: "page"`이고 원하는 URL을 가진 항목의 `id`를 골라 다음 형태로 WebSocket URL을 만든다:
`ws://localhost:<CDP_PORT>/devtools/page/<id>`

## 3. cdp_client.js로 조작 — 스크린샷 대신 텍스트로

```bash
cd "$REPO_DIR/scripts"
PAGE="ws://localhost:<CDP_PORT>/devtools/page/<id>"

# 페이지 전체 텍스트 추출 (크롤링의 핵심 — 화면을 안 찍어도 된다)
node cdp_client.js "$PAGE" evaluate '{"expression":"document.body.innerText"}'

# 특정 엘리먼트 클릭 (CSS selector로 안 잡히면 텍스트 매칭으로 직접 evaluate 짜서 클릭)
node cdp_client.js "$PAGE" click '{"selector":"#submit-button"}'

# 텍스트로 라벨을 찾아 클릭하는 패턴 (메뉴/라디오/탭 등 selector가 불안정할 때)
node cdp_client.js "$PAGE" evaluate '{"expression":"(function(){const els=Array.from(document.querySelectorAll(\"label\"));const l=els.find(x=>x.textContent.trim()===\"원하는 메뉴명\");if(!l)return \"NOT_FOUND\";l.click();return \"CLICKED\";})()"}'

# 필요할 때만 스크린샷(사람에게 보여주거나 레이아웃 확인용)
node cdp_client.js "$PAGE" screenshot > /tmp/shot.b64 && base64 -d /tmp/shot.b64 > /tmp/shot.png

# 페이지 이동
node cdp_client.js "$PAGE" navigate '{"url":"https://example.com"}'
```

**로그인 폼 채우기 — 비밀번호를 절대 커맨드라인 인자나 대화 로그에 남기지 말 것:**

```bash
export CDP_LOGIN_ID="$USER_ID"
export CDP_LOGIN_PASSWORD="$THE_PASSWORD"   # .env에서 source, echo로 출력 금지
node cdp_client.js "$PAGE" login '{"userSelector":"#USER","passSelector":"#PASSWORD"}'
unset CDP_LOGIN_PASSWORD
```

`login` 서브커맨드는 `process.env`에서만 자격증명을 읽으므로 이 값이 argv나 로그에 노출되지
않는다.

## 4. 로딩 대기 — "이전 화면이 섞여서 나오는" 실수를 피하는 법

Streamlit 같은 SPA는 메뉴 클릭 후 데이터가 비동기로 로드된다. **클릭 직후 바로 추출하면
이전 화면 내용이 남아있거나 로딩 중 텍스트("Running _...", "계산 중...", "조회 중...")가
섞여 나온다.** 아래처럼 안정화될 때까지 폴링할 것:

```bash
extract_stable() {
  for i in 1 2 3 4 5 6; do
    sleep 4
    node cdp_client.js "$PAGE" evaluate '{"expression":"document.body.innerText"}' > "$1"
    grep -q "Running _\|계산 중\|조회 중\|Loading" "$1" || return
  done
}
```

**클릭과 추출은 항상 짝을 맞출 것** — 재추출할 때 클릭을 빼먹으면(예: 재시도 루프에서)
방금 전 클릭한 다른 메뉴의 내용을 계속 읽게 되는 실수를 하기 쉽다(실제로 겪은 실수).

폼이 아주 짧은 시간(1초 이내) 안에 자동 리셋되는 사이트라면, 클릭→입력→제출을 **하나의
호출 안에서** 끝내야 한다 — 여러 번의 SSH/도구 호출로 나누면 그 틈을 반드시 놓친다.

## 5. 실패 시 처신 — 계정 잠금 등 부작용이 있는 자동화

로그인처럼 실패 시 부작용(계정 잠금 등)이 있는 작업은, 결과가 실패로 나오면 **원인이
확실하지 않은 한 재시도하지 말고 즉시 사용자에게 보고**한다. 자격증명 자체가 필드에
정확히 들어갔는지(길이 비교 등, 값 자체는 노출하지 않고)는 확인해도 되지만, "몇 번 더 해보면
되지 않을까"로 밀어붙이지 않는다.

## 6. 정리

```bash
cd "$REPO_DIR"
./scripts/steel_browser.sh stop <세션이름>
```

`PROFILE_DIR`(로그인 세션 유지용)을 마운트했다면 그 안의 파일이 컨테이너 안에서 root로
생성되어 호스트에서도 root 소유가 된다 — 일반 권한으로 못 지우면:

```bash
docker run --rm -v "$PROFILE_DIR:/cleanup" alpine rm -rf /cleanup/*
```

⚠️ **`docker rm -f`로 강제 종료한 뒤 같은 `PROFILE_DIR`로 재시작하면 Chrome이 안 뜬다** —
Chrome이 남긴 `SingletonLock` 등 잠금 파일이 이전 컨테이너를 가리킨 채 남아 새 컨테이너가
"다른 프로세스가 이 프로필을 쓰는 중"이라며 `POST /v1/sessions`가 `launch_failed`(
`process_singleton_posix.cc` 에러)로 실패한다. 재시작 전에 지울 것:

```bash
docker run --rm -v "$PROFILE_DIR:/data" alpine rm -f /data/Singleton*
```

## 참고

- 이 skill 자체의 소스는 `headless-browser-with-ai` 리포지토리의
  `.claude/skills/steel-cdp-browse/SKILL.md`이고, `make skill-install`로 `~/.claude/skills/`에
  복사되어 어느 프로젝트에서든 호출 가능해진다. 리포지토리를 업데이트한 뒤(`git pull`) skill
  내용도 최신화하려면 `make skill-install`을 다시 실행할 것.
- 자세한 배경(왜 xdotool 대신 CDP인지, Browserless와의 비교 등)은
  `headless-browser-with-ai/README.md`의 "참고: 유사 아키텍처와 개선 아이디어" 절 참고.
- `scripts/live_browser.sh`(Xvfb+x11vnc+noVNC 직접 조립)는 Docker를 못 쓰는 환경에서의
  대안이지만, `xdotool` 좌표 클릭에 의존해 이 skill보다 훨씬 취약하다.
