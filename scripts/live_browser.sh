#!/usr/bin/env bash
# 사람이 웹 브라우저(noVNC)로 접속해서 화면을 보며 직접 로그인/비밀번호를 입력할 수 있는
# "라이브" Chrome 세션을 띄운다. 로그인한 세션(쿠키 등)은 프로필 디렉터리에 영구 저장되어
# 다음 실행에도 그대로 유지된다.
#
# 여러 개를 동시에 띄울 수 있다 — 세션 이름(SESSION)마다 Xvfb 디스플레이 번호,
# VNC 포트, noVNC 웹 포트, Chrome 프로필을 자동으로 서로 겹치지 않게 할당하므로,
# 세션마다 별도의 웹 포트(noVNC 주소)로 개별 접속/조작할 수 있다.
#
# 구성: Xvfb(가상 디스플레이) -> Chrome(그 위에서 실제로 그려짐) -> x11vnc(화면을 VNC로 공유)
#       -> websockify+noVNC(VNC를 웹소켓으로 감싸 일반 브라우저에서 접속 가능하게 함)
#
# 사용법:
#   scripts/live_browser.sh start [URL] [SESSION]   # 세션 시작 (SESSION 기본값: default)
#   scripts/live_browser.sh stop [SESSION]          # 세션 종료
#   scripts/live_browser.sh status [SESSION]        # 특정 세션 상태 확인
#   scripts/live_browser.sh list                    # 실행 중인 모든 세션과 포트 목록
#
# 시작하면 세션별로 할당된 주소가 출력된다. 그 주소를 아무 브라우저에서나 열면
# 화면이 보이고 마우스/키보드로 그대로 조작(로그인 등)할 수 있다:
#   http://<이 서버의 IP>:<세션별 WEB_PORT>/vnc.html
#
# 필요 패키지: xvfb, x11vnc, websockify, novnc(→ /usr/share/novnc), google-chrome
#
# 세션별 포트/디스플레이는 기본적으로 자동 할당되지만, 아래 환경변수로 특정 값을
# 강제할 수도 있다(자동 할당을 건너뛴다):
#   DISPLAY_NUM   Xvfb 디스플레이 번호
#   VNC_PORT      x11vnc가 듣는 포트
#   WEB_PORT      noVNC(웹) 포트
#   PROFILE_DIR   Chrome 프로필(로그인 세션) 저장 위치 (기본: <repo>/live_profile/<SESSION>)
#   SCREEN_SIZE   (기본 1600x900x24) 가상 화면 해상도
#   VNC_PASSWORD  (기본 없음) 설정하면 noVNC 접속 시 이 비밀번호를 요구한다.
#                 설정하지 않으면 누구나 인증 없이 접속 가능하므로, 외부에서
#                 접근 가능한 네트워크라면 반드시 지정할 것.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SESSIONS_ROOT="$ROOT_DIR/.live_browser_run"
NOVNC_WEB_DIR="/usr/share/novnc"
SCREEN_SIZE="${SCREEN_SIZE:-1600x900x24}"

mkdir -p "$SESSIONS_ROOT"

# --- 포트/디스플레이 사용 여부 확인 ---------------------------------------
tcp_port_free() {
  ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

display_free() {
  [ ! -e "/tmp/.X11-unix/X$1" ]
}

# 백그라운드로 띄운 프로세스가 실제로 포트를 열 때까지 최대 5초 대기한다.
# (fixed sleep만으로는 시스템 부하 시 바인딩 전에 다음 단계로 넘어가는 경쟁 상태가 생길 수 있다)
wait_port_listening() {
  local port="$1" tries=0
  while tcp_port_free "$port"; do
    tries=$((tries + 1))
    if [ "$tries" -ge 50 ]; then
      return 1
    fi
    sleep 0.1
  done
}

wait_display_ready() {
  local n="$1" tries=0
  while display_free "$n"; do
    tries=$((tries + 1))
    if [ "$tries" -ge 50 ]; then
      return 1
    fi
    sleep 0.1
  done
}

find_free_port() {
  local port="$1"
  while ! tcp_port_free "$port"; do
    port=$((port + 1))
  done
  echo "$port"
}

find_free_display() {
  local n="$1"
  while ! display_free "$n"; do
    n=$((n + 1))
  done
  echo "$n"
}

# 이 서버의 IP를 추정해 접속 주소를 바로 복사해 쓸 수 있게 한다(여러 NIC가
# 있으면 첫 번째 것을 고르므로, 그게 아니라면 직접 확인해서 바꿀 것).
host_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

# --- 세션 디렉터리/상태 -----------------------------------------------------
session_dir() { echo "$SESSIONS_ROOT/$1"; }
pid_file() { echo "$(session_dir "$1")/$2.pid"; }
env_file() { echo "$(session_dir "$1")/session.env"; }

is_running() {
  local session="$1" name="$2" f
  f="$(pid_file "$session" "$name")"
  [ -f "$f" ] && kill -0 "$(cat "$f")" 2>/dev/null
}

session_running() { is_running "$1" xvfb; }

load_session_env() {
  local f
  f="$(env_file "$1")"
  [ -f "$f" ] && source "$f"
}

start() {
  local url="${1:-about:blank}"
  local session="${2:-default}"
  local sdir
  sdir="$(session_dir "$session")"
  mkdir -p "$sdir"

  if session_running "$session"; then
    echo "세션 '$session'은 이미 실행 중입니다. 'status $session'로 확인하세요." >&2
    exit 1
  fi

  local disp vport wport profile
  disp="${DISPLAY_NUM:-$(find_free_display 99)}"
  vport="${VNC_PORT:-$(find_free_port 5900)}"
  wport="${WEB_PORT:-$(find_free_port 6080)}"
  profile="${PROFILE_DIR:-$ROOT_DIR/live_profile/$session}"
  mkdir -p "$profile"

  {
    echo "DISPLAY_NUM=$disp"
    echo "VNC_PORT=$vport"
    echo "WEB_PORT=$wport"
    echo "PROFILE_DIR=$profile"
  } > "$(env_file "$session")"

  echo "[세션: $session] Xvfb :$disp 시작 ($SCREEN_SIZE)"
  Xvfb ":$disp" -screen 0 "$SCREEN_SIZE" -nolisten tcp \
    > "$sdir/xvfb.log" 2>&1 &
  echo $! > "$(pid_file "$session" xvfb)"
  wait_display_ready "$disp" || { echo "Xvfb 시작 실패 (디스플레이 :$disp)" >&2; exit 1; }

  echo "[세션: $session] x11vnc 시작 (VNC 포트 $vport)"
  if [ -n "${VNC_PASSWORD:-}" ]; then
    x11vnc -display ":$disp" -forever -shared -passwd "$VNC_PASSWORD" -rfbport "$vport" -quiet \
      > "$sdir/x11vnc.log" 2>&1 &
  else
    echo "  ⚠ VNC_PASSWORD가 설정되지 않아 인증 없이 접속 가능합니다." >&2
    x11vnc -display ":$disp" -forever -shared -nopw -rfbport "$vport" -quiet \
      > "$sdir/x11vnc.log" 2>&1 &
  fi
  echo $! > "$(pid_file "$session" x11vnc)"
  wait_port_listening "$vport" || { echo "x11vnc 시작 실패 (포트 $vport)" >&2; exit 1; }

  echo "[세션: $session] noVNC(websockify) 시작 (웹 포트 $wport)"
  websockify --web="$NOVNC_WEB_DIR" "$wport" "localhost:$vport" \
    > "$sdir/novnc.log" 2>&1 &
  echo $! > "$(pid_file "$session" novnc)"
  wait_port_listening "$wport" || { echo "websockify 시작 실패 (포트 $wport)" >&2; exit 1; }

  echo "[세션: $session] Chrome 시작 (프로필: $profile)"
  DISPLAY=":$disp" google-chrome \
    --no-sandbox \
    --user-data-dir="$profile" \
    --start-maximized \
    --no-first-run --no-default-browser-check \
    --disable-fre \
    "$url" \
    > "$sdir/chrome.log" 2>&1 &
  echo $! > "$(pid_file "$session" chrome)"

  local ip
  ip="$(host_ip)"

  echo
  echo "실행 완료. 아래 주소를 웹 브라우저로 열어 화면을 보며 로그인 등을 직접 진행하세요:"
  if [ -n "$ip" ]; then
    echo "  http://$ip:$wport/vnc.html"
  else
    echo "  http://<이 서버 IP>:$wport/vnc.html   (IP 자동 감지 실패, 직접 확인해서 채울 것)"
  fi
  echo "로그인한 세션은 '$profile' 에 저장되어 다음 실행에도 유지됩니다."
  echo "다른 세션을 추가로 띄우려면 SESSION 이름을 다르게 지정하세요: $0 start <URL> <다른이름>"
}

stop() {
  local session="${1:-default}"
  local sdir
  sdir="$(session_dir "$session")"
  if [ ! -d "$sdir" ]; then
    echo "세션 '$session'을 찾을 수 없습니다." >&2
    exit 1
  fi
  for name in chrome novnc x11vnc xvfb; do
    local f
    f="$(pid_file "$session" "$name")"
    if [ -f "$f" ]; then
      kill "$(cat "$f")" 2>/dev/null || true
      rm -f "$f"
    fi
  done
  rm -rf "$sdir"
  echo "세션 '$session'을 중지했습니다."
}

status() {
  local session="${1:-default}"
  if [ ! -d "$(session_dir "$session")" ]; then
    echo "세션 '$session': 존재하지 않음"
    return
  fi
  load_session_env "$session"
  echo "세션: $session (웹 포트: ${WEB_PORT:-?}, VNC 포트: ${VNC_PORT:-?}, DISPLAY: ${DISPLAY_NUM:-?})"
  for name in xvfb x11vnc novnc chrome; do
    if is_running "$session" "$name"; then
      echo "  $name: 실행 중 (pid $(cat "$(pid_file "$session" "$name")"))"
    else
      echo "  $name: 중지됨"
    fi
  done
}

list() {
  local found=0
  local ip
  ip="$(host_ip)"
  ip="${ip:-<이 서버 IP>}"
  if [ -d "$SESSIONS_ROOT" ]; then
    for sdir in "$SESSIONS_ROOT"/*/; do
      [ -d "$sdir" ] || continue
      local session
      session="$(basename "$sdir")"
      if session_running "$session"; then
        load_session_env "$session"
        echo "$session: http://$ip:${WEB_PORT:-?}/vnc.html (VNC ${VNC_PORT:-?}, DISPLAY ${DISPLAY_NUM:-?})"
        found=1
      fi
    done
  fi
  [ "$found" -eq 1 ] || echo "실행 중인 세션이 없습니다."
}

case "${1:-}" in
  start) start "${2:-}" "${3:-default}" ;;
  stop) stop "${2:-default}" ;;
  status) status "${2:-default}" ;;
  list) list ;;
  *) echo "사용법: $0 {start [URL] [SESSION]|stop [SESSION]|status [SESSION]|list}" >&2; exit 1 ;;
esac
