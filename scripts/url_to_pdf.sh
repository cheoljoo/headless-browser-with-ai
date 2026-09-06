#!/usr/bin/env bash
# URL을 headless Chrome으로 렌더링해 PDF(및 선택적으로 PNG)로 저장한다.
# AI 세션 없이 사람이 직접(또는 cron으로) 실행하는 것을 전제로 한다.
#
# 사용법:
#   url_to_pdf.sh <URL> [output_dir] [--png]
#
# 인자:
#   URL         (필수) 렌더링할 페이지 주소. http:// 또는 https:// 포함.
#   output_dir  (선택) 결과 파일을 저장할 디렉터리. 생략 시 이 스크립트 기준
#               상위 디렉터리의 ./output (즉 repo 루트의 output/).
#   --png       (선택) PDF 생성 후 페이지별 PNG(-01.png, -02.png, ...)도 함께 생성.
#
# 예시:
#   ./scripts/url_to_pdf.sh "http://psncs.iptime.org/stock_candle/"
#   ./scripts/url_to_pdf.sh "http://psncs.iptime.org/stock_candle/" ./output --png
#
# 요구 사항:
#   - google-chrome 또는 chromium(-browser) 실행 파일
#   - (PNG 변환 시) poppler-utils의 pdftoppm
#
# 출력 파일명: <output_dir>/<타임스탬프>_<URL슬러그>.pdf (PNG는 동일 접두사 + -NN.png)
set -euo pipefail

URL="${1:?사용법: $0 <URL> [output_dir] [--png]}"
OUT_DIR="${2:-$(dirname "$0")/../output}"
MAKE_PNG=0
for arg in "$@"; do
  [ "$arg" = "--png" ] && MAKE_PNG=1
done

# chromium 계열 중 시스템에 설치된 첫 번째 실행 파일을 사용한다.
CHROME_BIN="$(command -v google-chrome || command -v chromium || command -v chromium-browser)"
if [ -z "$CHROME_BIN" ]; then
  echo "google-chrome(또는 chromium)을 찾을 수 없습니다." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
# URL에서 스킴을 떼고 파일명에 쓸 수 없는 문자를 _ 로 치환해 슬러그로 사용.
SLUG="$(echo "$URL" | sed -E 's#^[a-z]+://##; s#[^A-Za-z0-9._-]+#_#g' | cut -c1-80)"
PDF_PATH="$OUT_DIR/${STAMP}_${SLUG}.pdf"

# 실행마다 독립된 프로필 디렉터리를 사용해 기존 Chrome 세션과 충돌을 피하고,
# 종료 시(성공/실패 무관) 임시 프로필을 정리한다.
PROFILE_DIR="$(mktemp -d)"
trap 'rm -rf "$PROFILE_DIR"' EXIT

# --virtual-time-budget: CDN 스크립트(tailwind/alpine 등) 로딩을 기다려주기 위한
# 가상 시간 예산(ms). 페이지가 무겁다면 이 값을 늘린다.
"$CHROME_BIN" \
  --headless --disable-gpu --no-sandbox \
  --user-data-dir="$PROFILE_DIR" \
  --print-to-pdf="$PDF_PATH" \
  --print-to-pdf-no-header --no-pdf-header-footer \
  --run-all-compositor-stages-before-draw \
  --virtual-time-budget=30000 \
  "$URL" >/dev/null 2>&1

if [ ! -s "$PDF_PATH" ]; then
  echo "PDF 생성 실패: $PDF_PATH" >&2
  exit 1
fi
echo "PDF 저장됨: $PDF_PATH"

if [ "$MAKE_PNG" -eq 1 ]; then
  if ! command -v pdftoppm >/dev/null; then
    echo "pdftoppm(poppler-utils)이 없어 PNG 변환을 건너뜁니다." >&2
  else
    PNG_PREFIX="$OUT_DIR/${STAMP}_${SLUG}"
    # -r 110: 110 DPI. 해상도를 높이려면 이 값을 조정(파일 크기도 함께 증가).
    pdftoppm -png -r 110 "$PDF_PATH" "$PNG_PREFIX"
    echo "PNG 저장됨: ${PNG_PREFIX}-*.png"
  fi
fi
