#!/usr/bin/env bash
# 오라클 클라우드 무료 VM 에 IT 자산관리 시스템을 설치한다.
#
# 서버에 SSH 로 접속한 뒤, 프로젝트 폴더에서 한 번만 실행하면 된다.
#
#   sudo bash deploy/oracle-setup.sh
#
# 하는 일
#   1. Docker 설치 (이미 있으면 건너뜀)
#   2. 서버 방화벽에 접속 포트 열기  ← 오라클에서 가장 많이 막히는 부분
#   3. 서비스 설정 생성과 기동
#   4. 외부 접속 주소 안내
#
# 주의: 오라클 콘솔의 '수신 규칙(Ingress Rule)' 은 웹 화면에서 직접 열어야 한다.
#       이 스크립트는 서버 안쪽 방화벽만 처리한다. (deploy/README-ORACLE.md 참고)

set -euo pipefail

PORT="${1:-8000}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

info() { echo "  $*"; }
ok()   { echo "  ✔ $*"; }
fail() { echo "  ✘ $*" >&2; }
step() { echo ""; echo "  ── $* ──────────────────────────────"; }

if [ "$(id -u)" -ne 0 ]; then
    fail "관리자 권한이 필요합니다.  sudo bash deploy/oracle-setup.sh  로 실행해 주세요."
    exit 1
fi

# 스크립트를 sudo 로 돌리므로, 원래 로그인한 사용자를 기억해 둔다
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

echo ""
echo "  ================================================"
echo "   IT 자산관리 시스템 - 오라클 클라우드 설치"
echo "  ================================================"
info "설치 경로: $PROJECT_DIR"
info "접속 포트: $PORT"

# ── 배포판 확인 ───────────────────────────────────
OS_ID=""
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
fi
info "운영체제: ${PRETTY_NAME:-알 수 없음} ($(uname -m))"

# ── 1) Docker 설치 ────────────────────────────────
step "1/4  Docker 준비"
if docker compose version >/dev/null 2>&1; then
    ok "Docker 가 이미 설치되어 있습니다"
else
    info "Docker 를 설치합니다... (2~3분 걸립니다)"
    case "$OS_ID" in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq ca-certificates curl
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" \
                -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${OS_ID} ${VERSION_CODENAME} stable" \
                > /etc/apt/sources.list.d/docker.list
            apt-get update -qq
            apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin
            ;;
        ol|oracle|rhel|centos|rocky|almalinux)
            dnf install -y -q dnf-utils
            dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            dnf install -y -q docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin
            ;;
        *)
            fail "지원하지 않는 배포판입니다: ${OS_ID:-알 수 없음}"
            info "Ubuntu 22.04/24.04 또는 Oracle Linux 로 VM 을 만들어 주세요."
            exit 1
            ;;
    esac
    # 오라클 VM 에는 systemd 가 있다. 없는 환경(컨테이너 등)에서는 건너뛴다.
    if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
        systemctl enable --now docker
        ok "Docker 설치 완료 (부팅 시 자동 시작 설정됨)"
    else
        info "systemd 가 없어 자동 시작 설정은 건너뜁니다"
        ok "Docker 설치 완료"
    fi
fi

# sudo 없이 docker 를 쓸 수 있게 해 둔다 (다음 로그인부터 적용)
if [ "$REAL_USER" != "root" ]; then
    usermod -aG docker "$REAL_USER" 2>/dev/null || true
    info "'$REAL_USER' 계정을 docker 그룹에 추가했습니다 (다시 로그인하면 sudo 없이 쓸 수 있습니다)"
fi

# ── 2) 서버 방화벽 열기 ────────────────────────────
step "2/4  서버 방화벽에 포트 $PORT 열기"
# 오라클의 기본 이미지는 iptables 로 대부분의 포트를 막아 둔다.
# 콘솔에서 수신 규칙만 열고 여기를 빼먹으면 "접속이 안 된다"가 된다.
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null
    firewall-cmd --reload >/dev/null
    ok "firewalld 에 ${PORT}/tcp 를 허용했습니다"
elif command -v iptables >/dev/null 2>&1; then
    # 검사(-C)와 추가(-I)는 규칙 내용이 완전히 같아야 한다.
    # 다르면 이미 있는 규칙을 못 찾아, 실행할 때마다 같은 규칙이 쌓인다.
    RULE=(-p tcp --dport "$PORT" -m state --state NEW,ESTABLISHED -j ACCEPT)
    if iptables -C INPUT "${RULE[@]}" 2>/dev/null; then
        ok "iptables 에 이미 ${PORT} 번이 열려 있습니다"
    else
        # 오라클 기본 이미지에는 뒤쪽에 REJECT 규칙이 있으므로 맨 앞에 넣는다
        iptables -I INPUT 1 "${RULE[@]}"
        ok "iptables 에 ${PORT}/tcp 를 허용했습니다"
    fi

    # 재부팅 후에도 유지되도록 저장한다
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1 && ok "방화벽 규칙을 저장했습니다"
    elif [ -d /etc/iptables ]; then
        iptables-save > /etc/iptables/rules.v4 && ok "방화벽 규칙을 저장했습니다"
    else
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y -qq iptables-persistent >/dev/null 2>&1 || true
        if command -v netfilter-persistent >/dev/null 2>&1; then
            netfilter-persistent save >/dev/null 2>&1 && ok "방화벽 규칙을 저장했습니다"
        else
            fail "방화벽 규칙을 저장하지 못했습니다. 재부팅하면 다시 막힐 수 있습니다."
        fi
    fi
else
    info "방화벽 도구를 찾지 못했습니다. 건너뜁니다."
fi

# ── 3) 서비스 설정과 기동 ──────────────────────────
step "3/4  서비스 설정과 기동"
if [ -f ".env" ]; then
    ok "설정 파일(.env)이 이미 있습니다"
else
    sudo -u "$REAL_USER" ./deploy.sh setup "$PORT" 2>/dev/null || ./deploy.sh setup "$PORT"
fi

info "이미지를 빌드하고 서비스를 시작합니다... (처음엔 3~5분 걸립니다)"
docker compose up -d --build

# ── 4) 접속 주소 안내 ──────────────────────────────
step "4/4  접속 확인"
for _ in $(seq 1 45); do
    if curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

if ! curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    fail "서비스가 뜨지 않았습니다.  docker compose logs  로 확인해 주세요."
    exit 1
fi
ok "서비스 정상 동작"

# 오라클은 공인 IP 를 랜카드에 직접 붙이지 않고 NAT 로 연결한다.
# 그래서 'hostname -I' 로는 사설 IP(10.0.0.x)만 보인다. 메타데이터에서 공인 IP 를 가져온다.
# 메타데이터 주소는 프록시를 거치면 안 된다 (--noproxy).
PUBLIC_IP=$(curl -s --max-time 5 --noproxy '*' -H "Authorization: Bearer Oracle" \
    http://169.254.169.254/opc/v2/vnics/ 2>/dev/null \
    | grep -oE '"publicIp"[[:space:]]*:[[:space:]]*"[0-9.]+"' \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
# 형식이 IP 가 아니면(오류 응답 등) 안내 문구로 대체한다
echo "$PUBLIC_IP" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' || PUBLIC_IP="<오라클 콘솔에 표시된 공인 IP>"

ADMIN_PW=$(grep -E '^ITAM_ADMIN_PASSWORD=' .env 2>/dev/null | cut -d= -f2 || echo "(.env 파일 참고)")

echo ""
echo "  ================================================"
echo "   설치가 끝났습니다"
echo "  ================================================"
echo ""
echo "     접속 주소 : http://${PUBLIC_IP}:${PORT}"
echo ""
echo "     아이디    : admin"
echo "     비밀번호  : ${ADMIN_PW}"
echo ""
echo "     첫 로그인 후 화면 우측 상단에서 비밀번호를 꼭 바꾸세요."
echo "  ------------------------------------------------"
echo ""
info "접속이 안 된다면, 오라클 콘솔에서 '수신 규칙'을 열었는지 확인하세요."
info "  콘솔 → 네트워킹 → 가상 클라우드 네트워크 → 서브넷 → 보안 목록 →"
info "  수신 규칙 추가 → 소스 0.0.0.0/0 , 대상 포트 ${PORT}"
echo ""
info "원인을 자동으로 짚어 보려면:  ./deploy.sh doctor"
echo ""
