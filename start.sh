#!/usr/bin/env bash
# IT 자산관리 시스템 - 내 컴퓨터에서 실행하기 (macOS / 리눅스)
#
#   터미널에서:  ./start.sh
#   종료:        Ctrl+C

set -euo pipefail
cd "$(dirname "$0")"

echo ""
echo "  ================================================"
echo "   IT 자산관리 시스템 - 내 컴퓨터에서 실행하기"
echo "  ================================================"
echo ""

# ── 1) 파이썬 찾기 ────────────────────────────────
PY=""
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
        # 3.10 이상인지 확인한다
        if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
            PY="$candidate"
            break
        fi
    fi
done

if [ -z "$PY" ]; then
    echo "  [!] 파이썬 3.10 이상이 필요합니다."
    echo ""
    echo "      macOS  : brew install python3"
    echo "               (Homebrew 가 없다면 https://www.python.org/downloads/ 에서 설치)"
    echo "      Ubuntu : sudo apt install python3 python3-venv"
    echo ""
    exit 1
fi
echo "  [1/4] 파이썬 확인: $("$PY" --version 2>&1)"

# ── 2) 실행 환경 준비 ─────────────────────────────
VENV_PY=".venv/bin/python"
if [ ! -x "$VENV_PY" ]; then
    echo "  [2/4] 실행 환경을 만드는 중입니다... (처음 한 번만, 1~2분 걸립니다)"
    "$PY" -m venv .venv
else
    echo "  [2/4] 실행 환경 확인"
fi

echo "  [3/4] 필요한 패키지를 확인하는 중입니다..."
"$VENV_PY" -m pip install --quiet --upgrade pip
"$VENV_PY" -m pip install --quiet -r requirements.txt

# ── 3) 로그인 세션 키 (없으면 만들어 두고 계속 재사용) ──
# 이 값이 매번 바뀌면 서버를 다시 켤 때마다 로그인이 풀린다.
if [ ! -f ".local-secret" ]; then
    "$VENV_PY" -c "import secrets; open('.local-secret','w').write(secrets.token_hex(32))"
    chmod 600 .local-secret
fi
export ITAM_SECRET_KEY
ITAM_SECRET_KEY=$(cat .local-secret)

export ITAM_RELOAD=0
# 포트는 첫 번째 인자로 바꿀 수 있다.  예)  ./start.sh 8001
export ITAM_PORT="${1:-${ITAM_PORT:-8000}}"

# 이미 다른 프로그램이 그 포트를 쓰고 있으면 미리 알려 준다.
# (안 그러면 서버가 그냥 죽어버려 원인을 알기 어렵다)
if ! "$VENV_PY" -c "
import os, socket, sys
sock = socket.socket()
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    sock.bind(('0.0.0.0', int(os.environ['ITAM_PORT'])))
except OSError:
    sys.exit(1)
finally:
    sock.close()
" 2>/dev/null; then
    echo ""
    echo "  [!] ${ITAM_PORT} 번 포트를 이미 다른 프로그램이 쓰고 있습니다."
    echo ""
    echo "      이 프로그램이 이미 실행 중일 수도 있습니다."
    echo "      먼저 http://localhost:${ITAM_PORT} 로 접속해 보세요."
    echo ""
    echo "      다른 포트로 실행하려면:   ./start.sh 8001"
    echo ""
    exit 1
fi

# ── 4) 처음 실행이면 샘플 데이터를 넣을지 물어본다 ──
if [ ! -f "data/itam.db" ]; then
    echo ""
    printf "  처음 실행이군요. 둘러보기 좋게 샘플 데이터를 넣을까요? (y/N) "
    read -r answer
    case "$answer" in
        [Yy]*) "$VENV_PY" seed_demo.py ;;
    esac
fi

echo ""
echo "  [4/4] 서버를 시작합니다."
echo ""
echo "  ------------------------------------------------"
echo "   브라우저에서 아래 주소로 접속하세요"
echo ""
echo "       http://localhost:${ITAM_PORT}"
echo ""
echo "   최초 관리자 계정   아이디: admin   비밀번호: admin1234"
echo ""
echo "   종료하려면 Ctrl+C 를 누르세요."
echo "  ------------------------------------------------"
echo ""

# 브라우저를 자동으로 열어 준다 (실패해도 서버는 그대로 뜬다)
( sleep 2
  if command -v open >/dev/null 2>&1; then
      open "http://localhost:${ITAM_PORT}" 2>/dev/null || true
  elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "http://localhost:${ITAM_PORT}" 2>/dev/null || true
  fi ) &

exec "$VENV_PY" run.py
