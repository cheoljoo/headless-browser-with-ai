#!/usr/bin/env bash
# live_browser.sh(Xvfb+x11vnc+noVNC)와 같은 목적을, 자체 조립 대신
# self-host Steel(https://steel.dev/, https://github.com/steel-dev/steel-browser)
# 컨테이너로 구현한 버전이다. 하나의 Docker 컨테이너가 "브라우저 서버"가 되어
# - 사람: 웹 UI(Session Player)로 화면을 보며 로그인 등 직접 개입
# - AI: CDP(Chrome DevTools Protocol)로 DOM을 조회하고 정밀하게 클릭/입력
# 두 채널을 함께 제공한다. live_browser.sh처럼 세션(SESSION) 이름마다 포트를
# 자동으로 겹치지 않게 할당해 여러 개를 동시에 띄울 수 있다.
#
# 사용법:
#   scripts/steel_browser.sh start [URL] [SESSION]   # 세션 시작 (SESSION 기본값: default)
#   scripts/steel_browser.sh stop [SESSION]          # 세션 종료 (컨테이너 삭제)
#   scripts/steel_browser.sh status [SESSION]        # 특정 세션 상태 확인
#   scripts/steel_browser.sh list                    # 실행 중인 모든 세션과 주소 목록
#
# 시작하면 세 가지 주소가 출력된다:
#   Live View(Session Player) : 사람이 브라우저로 열어 화면을 보며 조작하는 곳
#   Dashboard(UI)             : 세션 목록/설정을 보는 곳
#   CDP endpoint              : Playwright/Puppeteer가 connectOverCDP로 붙는 곳
#
# 필요한 것: docker (ghcr.io/steel-dev/steel-browser 이미지를 최초 1회 pull한다)
#
# 세션별 포트는 기본적으로 자동 할당되지만, 아래 환경변수로 강제할 수 있다:
#   API_PORT      Steel 서버(웹 UI/REST API) 포트 (기본: 3000부터 자동 할당)
#   CDP_PORT      CDP(원격 디버깅) 포트 (기본: 9223부터 자동 할당)
#   WIDTH/HEIGHT  세션 뷰포트 크기 (기본: 1600/900)
#   PROFILE_DIR   Chrome 프로필(로그인 세션) 저장 위치 (기본: <repo>/steel_profile/<SESSION>)
#
# 주의: PROFILE_DIR을 컨테이너의 /tmp/steel-chrome 에 마운트해 재시작 후에도
# 로그인 세션이 유지되게 하는데, 이 경로는 steel-browser가 공식 문서화한
# 계약이 아니라 실행 로그에서 관찰한 내부 구현 경로다. 이미지가 업데이트되면
# 깨질 수 있으니, 로그인 유지가 꼭 필요하면 실행 후 `docker logs`로
# `userDataDir` 값이 여전히 `/tmp/steel-chrome`인지 확인할 것.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SESSIONS_ROOT="$ROOT_DIR/.steel_browser_run"
IMAGE="ghcr.io/steel-dev/steel-browser"
WIDTH="${WIDTH:-1600}"
HEIGHT="${HEIGHT:-900}"

mkdir -p "$SESSIONS_ROOT"

container_name() { echo "steel-browser-$1"; }
session_dir() { echo "$SESSIONS_ROOT/$1"; }
env_file() { echo "$(session_dir "$1")/session.env"; }

tcp_port_free() {
  ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

find_free_port() {
  local port="$1"
  while ! tcp_port_free "$port"; do
    port=$((port + 1))
  done
  echo "$port"
}

# 이 서버의 IP를 추정해 접속 주소를 바로 복사해 쓸 수 있게 한다(여러 NIC가
# 있으면 첫 번째 것을 고르므로, 그게 아니라면 직접 확인해서 바꿀 것).
host_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

wait_api_ready() {
  local port="$1" tries=0
  while ! curl -sf "http://127.0.0.1:$port/v1/sessions" >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -ge 100 ]; then
      return 1
    fi
    sleep 0.2
  done
}

container_running() {
  docker ps --format '{{.Names}}' | grep -qx "$(container_name "$1")"
}

load_session_env() {
  local f
  f="$(env_file "$1")"
  [ -f "$f" ] && source "$f"
}

start() {
  local url="${1:-}"
  local session="${2:-default}"
  local sdir
  sdir="$(session_dir "$session")"
  mkdir -p "$sdir"

  if container_running "$session"; then
    echo "세션 '$session'은 이미 실행 중입니다. 'status $session'로 확인하세요." >&2
    exit 1
  fi

  local api_port cdp_port profile ip
  api_port="${API_PORT:-$(find_free_port 3000)}"
  cdp_port="${CDP_PORT:-$(find_free_port 9223)}"
  profile="${PROFILE_DIR:-$ROOT_DIR/steel_profile/$session}"
  mkdir -p "$profile"
  ip="$(host_ip)"

  {
    echo "API_PORT=$api_port"
    echo "CDP_PORT=$cdp_port"
    echo "PROFILE_DIR=$profile"
  } > "$(env_file "$session")"

  echo "[세션: $session] Steel 컨테이너 시작 (API 포트 $api_port, CDP 포트 $cdp_port)"
  # DOMAIN을 안 주면 steel-browser가 자기 주소를 기본값 0.0.0.0으로 알고 있어서, Live View
  # 페이지(HTML)에 박히는 WebSocket 접속 주소도 ws://0.0.0.0:<PORT>/...가 된다. 이건 그 페이지를
  # 보는 사람 브라우저 입장에서 "0.0.0.0=자기 자신의 PC"로 풀리므로, 원격(예: Windows)에서
  # noVNC처럼 접속하면 화면이 "Session Offline"으로 뜨는 원인이 된다(포트포워딩 문제가 아님 —
  # CDP/REST API 자체는 정상 동작하는데 이 HTML에 박히는 값만 잘못됨). 실제로 외부에서 접속할
  # host:port를 DOMAIN으로 명시해 이 문제를 막는다.
  local domain="${DOMAIN:-}"
  [ -z "$domain" ] && [ -n "$ip" ] && domain="$ip:$api_port"
  if [ -z "$domain" ]; then
    echo "  ⚠ 이 서버의 IP를 자동 감지하지 못해 DOMAIN을 못 넣었습니다 — Live View가 외부에서" >&2
    echo "    'Session Offline'으로 보일 수 있습니다. 필요하면 DOMAIN=<IP>:$api_port 환경변수로 직접 지정할 것." >&2
  fi

  docker run -d --name "$(container_name "$session")" \
    -p "$api_port:3000" -p "$cdp_port:9223" \
    ${domain:+-e "DOMAIN=$domain"} \
    -v "$profile:/tmp/steel-chrome" \
    "$IMAGE" > "$sdir/container_id" 2> "$sdir/docker_run.log" \
    || { echo "docker run 실패 (자세한 내용: $sdir/docker_run.log)" >&2; exit 1; }

  echo "[세션: $session] Steel API 준비 대기 중..."
  wait_api_ready "$api_port" || { echo "Steel API가 뜨지 않았습니다 (docker logs $(container_name "$session") 확인)" >&2; exit 1; }

  echo "[세션: $session] 세션 생성 중..."
  curl -sf -X POST "http://127.0.0.1:$api_port/v1/sessions" \
    -H "Content-Type: application/json" \
    -d "{\"dimensions\":{\"width\":$WIDTH,\"height\":$HEIGHT}}" > "$sdir/session.json" \
    || { echo "세션 생성 실패 (자세한 내용: $sdir/session.json)" >&2; exit 1; }

  if [ -n "$url" ]; then
    echo "[세션: $session] $url 로 이동 중..."
    local encoded_url
    encoded_url="$(python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=''))" "$url")"
    curl -sf -X PUT "http://127.0.0.1:$cdp_port/json/new?$encoded_url" > "$sdir/navigate.json" \
      || echo "  ⚠ 페이지 이동 실패 (CDP가 아직 준비 안 됐을 수 있음, 잠시 후 재시도해볼 것)" >&2
  fi

  local ip
  ip="$(host_ip)"
  ip="${ip:-<이 서버 IP>}"

  echo
  echo "실행 완료. 아래 주소들을 참고하세요:"
  echo "  Live View(사람이 화면 보며 조작) : http://$ip:$api_port/v1/sessions/debug"
  echo "  Dashboard(세션 목록/설정)        : http://$ip:$api_port/ui"
  echo "  CDP endpoint(AI/Playwright용)   : http://$ip:$cdp_port  (connectOverCDP)"
  echo "로그인한 세션은 '$profile' 에 저장 시도되며(실험적, 위 주의 참고), 컨테이너를 지우지 않는 한 유지됩니다."
  echo "다른 세션을 추가로 띄우려면 SESSION 이름을 다르게 지정하세요: $0 start <URL> <다른이름>"
}

stop() {
  local session="${1:-default}"
  if ! docker ps -a --format '{{.Names}}' | grep -qx "$(container_name "$session")"; then
    echo "세션 '$session'을 찾을 수 없습니다." >&2
    exit 1
  fi
  docker rm -f "$(container_name "$session")" >/dev/null
  rm -rf "$(session_dir "$session")"
  echo "세션 '$session'을 중지했습니다."
}

status() {
  local session="${1:-default}"
  if [ ! -d "$(session_dir "$session")" ]; then
    echo "세션 '$session': 존재하지 않음"
    return
  fi
  load_session_env "$session"
  echo "세션: $session (API 포트: ${API_PORT:-?}, CDP 포트: ${CDP_PORT:-?})"
  if container_running "$session"; then
    echo "  컨테이너: 실행 중"
    local count
    count=$(curl -sf "http://127.0.0.1:${API_PORT:-0}/v1/sessions" 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('sessions', [])))" 2>/dev/null || echo "?")
    echo "  활성 Steel 세션 수: $count"
  else
    echo "  컨테이너: 중지됨"
  fi
}

list() {
  local found=0
  local ip
  ip="$(host_ip)"
  ip="${ip:-<이 서버 IP>}"
  for name in $(docker ps --format '{{.Names}}' | grep '^steel-browser-' || true); do
    local session="${name#steel-browser-}"
    load_session_env "$session"
    echo "$session: http://$ip:${API_PORT:-?}/v1/sessions/debug (CDP ${CDP_PORT:-?})"
    found=1
  done
  [ "$found" -eq 1 ] || echo "실행 중인 세션이 없습니다."
}

case "${1:-}" in
  start) start "${2:-}" "${3:-default}" ;;
  stop) stop "${2:-default}" ;;
  status) status "${2:-default}" ;;
  list) list ;;
  *) echo "사용법: $0 {start [URL] [SESSION]|stop [SESSION]|status [SESSION]|list}" >&2; exit 1 ;;
esac
