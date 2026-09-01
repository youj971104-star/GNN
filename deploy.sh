#!/usr/bin/env bash
# IT 자산관리 시스템 배포 도우미
#
#   ./deploy.sh setup     최초 1회 - 설정 파일(.env) 생성
#   ./deploy.sh start     서비스 시작 (없으면 이미지도 빌드)
#   ./deploy.sh stop      서비스 중지
#   ./deploy.sh restart   재시작
#   ./deploy.sh update    최신 코드로 다시 빌드하고 재시작
#   ./deploy.sh logs      실행 로그 보기
#   ./deploy.sh status    상태 확인
#   ./deploy.sh backup    데이터베이스 백업
#   ./deploy.sh restore <파일>   백업 파일로 되돌리기
#   ./deploy.sh demo      샘플 데이터 넣기 (처음 둘러볼 때만)

set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE=".env"
SERVICE="app"
CONTAINER="itam-app"
APP_UID="10001"   # Dockerfile 에서 만든 itam 계정의 uid

# docker compose / docker-compose 어느 쪽이든 동작하게 한다
if docker compose version >/dev/null 2>&1; then
    DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DC="docker-compose"
else
    echo "[오류] Docker Compose 를 찾을 수 없습니다. Docker 를 먼저 설치해 주세요."
    echo "       설치 안내: https://docs.docker.com/engine/install/"
    exit 1
fi

info()  { echo "  $*"; }
ok()    { echo "  ✔ $*"; }
fail()  { echo "  ✘ $*" >&2; }

require_env() {
    if [ ! -f "$ENV_FILE" ]; then
        fail "설정 파일(.env)이 없습니다. 먼저 './deploy.sh setup' 을 실행해 주세요."
        exit 1
    fi
}

# 도커가 쓰는 게이트웨이 주소들 (172.17.0.1 같은 것).
# 이 주소는 서버 자신만 아는 값이라, 다른 PC 에서 접속할 때 쓰면 안 된다.
# 대역으로 거르면 172.16.0.0/12 을 사내망으로 쓰는 회사에서 진짜 주소까지
# 사라지므로, 도커에 직접 물어 정확한 값만 제외한다.
docker_gateway_ips() {
    docker network ls -q 2>/dev/null \
        | xargs -r docker network inspect \
            --format '{{range .IPAM.Config}}{{println .Gateway}}{{end}}' 2>/dev/null \
        | grep -E '^[0-9]' || true
}

# 다른 PC 에서 접속할 때 쓸 수 있는 이 서버의 주소 목록
list_host_ips() {
    local candidates excluded candidate
    excluded=$(docker_gateway_ips)

    if command -v ip >/dev/null 2>&1; then
        candidates=$(ip -o -4 addr show 2>/dev/null \
            | awk '$2 !~ /^(lo|docker|br-|veth|virbr|tun|tap)/ {print $4}' \
            | cut -d/ -f1 || true)
    else
        candidates=$(hostname -I 2>/dev/null | tr ' ' '\n' \
            | grep -E '^[0-9]' | grep -vE '^(127\.|169\.254\.)' || true)
    fi

    for candidate in $candidates; do
        if ! echo "$excluded" | grep -qx "$candidate"; then
            echo "$candidate"
        fi
    done
}

# 안내에 쓸 대표 주소 하나를 고른다.
# 'hostname -I' 첫 값을 그냥 쓰면 도커 내부 주소를 알려주게 되는 일이 있어,
# 바깥으로 나가는 경로에 실제로 쓰이는 주소를 우선한다.
guess_host_ip() {
    local ip=""

    # 1순위: 외부로 나갈 때 사용하는 인터페이스의 주소 (가장 정확하다)
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oE 'src [0-9.]+' | awk '{print $2}') || true
    fi

    # 2순위: macOS
    if [ -z "$ip" ]; then
        ip=$(ipconfig getifaddr en0 2>/dev/null) || true
        [ -z "$ip" ] && ip=$(ipconfig getifaddr en1 2>/dev/null) || true
    fi

    # 3순위: 후보 목록의 첫 번째
    [ -z "$ip" ] && ip=$(list_host_ips | head -1)

    [ -z "$ip" ] && ip="<서버IP>"
    echo "$ip"
}

cmd_setup() {
    if [ -f "$ENV_FILE" ]; then
        fail "이미 .env 파일이 있습니다. 다시 만들려면 파일을 지우고 실행해 주세요."
        exit 1
    fi

    local secret admin_password port
    secret=$(python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null \
        || openssl rand -hex 32)
    admin_password=$(python3 -c "import secrets,string; print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range(12)))" 2>/dev/null \
        || openssl rand -base64 12 | tr -d '/+=')
    port="${1:-8000}"

    cat > "$ENV_FILE" <<ENVEOF
# IT 자산관리 시스템 설정 - $(date '+%Y-%m-%d %H:%M') 생성
# 이 파일에는 비밀 값이 들어 있습니다. 외부에 공유하거나 git 에 올리지 마세요.

# 세션 서명 키 (바꾸면 모든 사용자의 로그인이 풀립니다)
ITAM_SECRET_KEY=$secret

# 접속 포트 - http://<서버IP>:<이 포트> 로 접속합니다
ITAM_PUBLIC_PORT=$port

# 최초 관리자 계정 (첫 로그인 후 화면에서 비밀번호를 변경하세요)
ITAM_ADMIN_USERNAME=admin
ITAM_ADMIN_PASSWORD=$admin_password

# 워커 프로세스 수 (직원 100명 규모면 2개로 충분합니다)
ITAM_WORKERS=2

# 목록 한 페이지 행 수 / 로그인 유지 시간(초) / 엑셀 업로드 최대 크기(바이트)
ITAM_PAGE_SIZE=20
ITAM_SESSION_MAX_AGE=43200
ITAM_MAX_UPLOAD_BYTES=10485760

# 도메인 + HTTPS 로 전환하면 1 로 바꾸세요 (deploy/README-HTTPS.md 참고)
ITAM_HTTPS_ONLY=0
ENVEOF
    chmod 600 "$ENV_FILE"
    mkdir -p backups

    echo ""
    ok "설정 파일(.env)을 만들었습니다."
    echo ""
    echo "  ── 최초 관리자 계정 ─────────────────────────────"
    echo "     아이디   : admin"
    echo "     비밀번호 : $admin_password"
    echo "  ─────────────────────────────────────────────────"
    echo "     이 비밀번호는 .env 파일에도 저장되어 있습니다."
    echo "     첫 로그인 후 화면에서 반드시 변경해 주세요."
    echo ""
    info "이제 './deploy.sh start' 로 서비스를 시작하세요."
}

cmd_start() {
    require_env
    mkdir -p backups
    info "이미지를 준비하고 서비스를 시작합니다..."
    $DC up -d --build

    info "서비스가 올라오기를 기다리는 중..."
    local port; port=$(grep -E '^ITAM_PUBLIC_PORT=' "$ENV_FILE" | cut -d= -f2)
    port="${port:-8000}"
    for _ in $(seq 1 30); do
        if curl -fsS "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
            echo ""
            ok "정상적으로 시작되었습니다."
            echo ""
            echo "  ── 접속 주소 ───────────────────────────────────"
            echo "     이 서버에서      : http://localhost:${port}"
            echo "     다른 PC 에서     : http://$(guess_host_ip):${port}"
            echo "  ────────────────────────────────────────────────"
            echo ""
            info "다른 PC 에서 접속이 안 되면 서버 방화벽에서 ${port} 번 포트를 열어야 합니다."
            info "원인을 자동으로 짚어 보려면:  ./deploy.sh doctor"
            echo ""
            return 0
        fi
        sleep 2
    done

    fail "시작 확인에 실패했습니다. './deploy.sh logs' 로 로그를 확인해 주세요."
    exit 1
}

cmd_stop() {
    $DC down
    ok "서비스를 중지했습니다. (자산 데이터는 그대로 보존됩니다)"
}

cmd_restart() { require_env; $DC restart "$SERVICE"; ok "재시작했습니다."; }

cmd_update() {
    require_env
    info "최신 코드로 다시 빌드합니다..."
    $DC up -d --build
    ok "업데이트를 마쳤습니다."
}

cmd_logs()   { $DC logs -f --tail=100 "$SERVICE"; }

cmd_status() {
    $DC ps
    echo ""
    local port; port=$(grep -E '^ITAM_PUBLIC_PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo 8000)
    if curl -fsS "http://127.0.0.1:${port:-8000}/healthz" >/dev/null 2>&1; then
        ok "서비스 정상 (http://$(guess_host_ip):${port:-8000})"
    else
        fail "서비스에 응답이 없습니다."
    fi
}

cmd_backup() {
    mkdir -p backups
    local name="itam-$(date '+%Y%m%d-%H%M%S').db"

    # SQLite 온라인 백업 API 를 쓰므로 서비스가 돌아가는 중에도 안전하다.
    # 컨테이너 볼륨 안에 만든 뒤 호스트로 꺼내면 폴더 권한 문제를 겪지 않는다.
    $DC exec -T "$SERVICE" python -m app.backup "/data/backups/${name}" >/dev/null
    docker cp "${CONTAINER}:/data/backups/${name}" "backups/${name}"
    $DC exec -T "$SERVICE" rm -f "/data/backups/${name}"

    ok "백업 완료: backups/${name}  ($(du -h "backups/${name}" | cut -f1))"
    info "보관 중인 백업: $(ls -1 backups/*.db 2>/dev/null | wc -l)개"
}

cmd_restore() {
    local file="${1:-}"
    if [ -z "$file" ] || [ ! -f "$file" ]; then
        fail "되돌릴 백업 파일을 지정해 주세요.  예) ./deploy.sh restore backups/itam-20260901-120000.db"
        echo ""
        info "사용 가능한 백업:"
        ls -1t backups/*.db 2>/dev/null | head -10 || info "(없음)"
        exit 1
    fi

    # 엉뚱한 파일로 되돌려 서비스가 죽는 일이 없도록 형식을 먼저 확인한다
    if [ "$(head -c 15 "$file")" != "SQLite format 3" ]; then
        fail "'$file' 은 SQLite 백업 파일이 아닙니다."
        exit 1
    fi

    echo ""
    echo "  현재 데이터를 '$file' 시점으로 되돌립니다."
    echo "  되돌린 뒤에는 지금 데이터로 돌아올 수 없습니다."
    printf "  계속하려면 'yes' 를 입력하세요: "
    read -r answer
    [ "$answer" = "yes" ] || { info "취소했습니다."; exit 0; }

    cmd_backup   # 만약을 위해 현재 상태를 먼저 백업해 둔다

    docker cp "$file" "${CONTAINER}:/data/_restore.db"
    $DC stop "$SERVICE"

    # WAL/SHM 파일까지 지워야 예전 데이터가 되살아나지 않는다.
    # docker cp 로 들어온 파일은 root 소유라, 앱 계정(uid 10001)이 쓸 수 있도록
    # 소유권을 넘겨줘야 한다. 그래서 이 정리 작업만 root 로 실행한다.
    $DC run --rm -T --user root --entrypoint sh "$SERVICE" -c \
        "cd /data && rm -f itam.db itam.db-wal itam.db-shm \
         && mv _restore.db itam.db && chown ${APP_UID}:${APP_UID} itam.db && chmod 644 itam.db"

    $DC start "$SERVICE"
    ok "복원을 마쳤습니다."
}

# 접속이 안 될 때 원인을 순서대로 짚어 준다
cmd_doctor() {
    local port failed=0
    port=$(grep -E '^ITAM_PUBLIC_PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 || true)
    port="${port:-8000}"

    echo ""
    echo "  IT 자산관리 시스템 접속 진단"
    echo "  ═══════════════════════════════════════════════"
    echo ""

    # 1. Docker 데몬
    if ! docker info >/dev/null 2>&1; then
        fail "Docker 가 실행되고 있지 않습니다."
        info "  → 리눅스:  sudo systemctl start docker"
        info "  → 윈도우/맥: Docker Desktop 을 실행해 주세요."
        return 1
    fi
    ok "Docker 실행 중"

    # 2. 설정 파일
    if [ ! -f "$ENV_FILE" ]; then
        fail "설정 파일(.env)이 없습니다."
        info "  → ./deploy.sh setup 을 먼저 실행하세요."
        return 1
    fi
    ok "설정 파일 확인 (접속 포트: ${port})"

    # 3. 컨테이너
    local state
    # 컨테이너가 아예 없으면 docker inspect 가 빈 줄을 남기므로 따로 정리한다
    state=$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null | tr -d '[:space:]' || true)
    [ -z "$state" ] && state="만들어지지 않음"
    if [ "$state" != "running" ]; then
        fail "컨테이너가 실행 중이 아닙니다. (상태: ${state})"
        info "  → ./deploy.sh start 로 시작하세요."
        info "  → 시작했는데도 이 상태라면: ./deploy.sh logs"
        return 1
    fi
    ok "컨테이너 실행 중"

    # 4. 서버 자신에서의 응답
    if curl -fsS --max-time 5 "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
        ok "서버 내부 응답 정상 (http://localhost:${port})"
    else
        fail "서버 안에서도 응답이 없습니다."
        info "  → 앱이 뜨는 중일 수 있습니다. 10초 뒤 다시 시도해 보세요."
        info "  → 계속 같다면: ./deploy.sh logs"
        return 1
    fi

    # 5. 포트가 서버 바깥으로 연결되어 있는지
    #    ss/netstat 는 설치되지 않은 서버가 많아, 도커에 직접 물어보는 편이 정확하다.
    local mapping
    mapping=$(docker port "$CONTAINER" 8000/tcp 2>/dev/null | head -1 || true)
    if [ -z "$mapping" ]; then
        fail "컨테이너 포트가 서버 바깥으로 연결되어 있지 않습니다."
        info "  → docker-compose.yml 의 ports 설정을 확인한 뒤 ./deploy.sh restart"
        failed=1
    elif echo "$mapping" | grep -q '^127\.0\.0\.1:'; then
        fail "포트가 이 서버 안에서만 열려 있습니다 (${mapping})."
        info "  → 다른 PC 에서 접속하려면 docker-compose.yml 의 ports 에서"
        info "     '127.0.0.1:' 부분을 지운 뒤 ./deploy.sh restart"
        failed=1
    else
        ok "포트 연결 확인 (${mapping} → 컨테이너 8000)"
    fi

    # 6. 방화벽 - 사내망에서 접속이 막히는 가장 흔한 원인이다
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        if ufw status 2>/dev/null | grep -q "${port}"; then
            ok "방화벽(ufw)에 포트 ${port} 허용됨"
        else
            fail "방화벽(ufw)이 켜져 있는데 포트 ${port} 가 허용되어 있지 않습니다."
            info "  → sudo ufw allow ${port}/tcp"
            failed=1
        fi
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        if firewall-cmd --list-ports 2>/dev/null | grep -q "${port}/tcp"; then
            ok "방화벽(firewalld)에 포트 ${port} 허용됨"
        else
            fail "방화벽(firewalld)이 켜져 있는데 포트 ${port} 가 허용되어 있지 않습니다."
            info "  → sudo firewall-cmd --permanent --add-port=${port}/tcp && sudo firewall-cmd --reload"
            failed=1
        fi
    else
        info "방화벽 설정을 확인하지 못했습니다 (ufw/firewalld 미사용)."
        info "  → 클라우드 서버라면 보안 그룹/방화벽 규칙에서 ${port} 번 포트를 열어야 합니다."
    fi

    # 7. 접속 주소 안내
    echo ""
    echo "  ── 접속 주소 ───────────────────────────────────"
    echo "     이 서버에서      : http://localhost:${port}"
    echo "     다른 PC 에서     : http://$(guess_host_ip):${port}"
    local others
    others=$(list_host_ips | grep -v "^$(guess_host_ip)$" | tr '\\n' ' ')
    if [ -n "$others" ]; then
        echo ""
        echo "     위 주소로 안 되면 아래 주소도 시도해 보세요:"
        for other in $others; do
            echo "       http://${other}:${port}"
        done
    fi
    echo "  ────────────────────────────────────────────────"
    echo ""

    if [ "$failed" -eq 0 ]; then
        ok "서버 쪽에는 문제가 없어 보입니다."
        info "그래도 안 된다면 접속하는 PC 가 같은 사내망에 있는지,"
        info "주소 앞에 https:// 가 아니라 http:// 를 썼는지 확인해 주세요."
    else
        fail "위에 표시된 항목을 먼저 해결해 주세요."
    fi
    echo ""
}

cmd_demo() {
    require_env
    $DC exec -T "$SERVICE" python seed_demo.py
    ok "샘플 데이터를 넣었습니다. (조회 전용 계정: viewer / viewer1234)"
}

case "${1:-}" in
    setup)   shift; cmd_setup "$@" ;;
    start|up)   cmd_start ;;
    stop|down)  cmd_stop ;;
    restart)    cmd_restart ;;
    update)     cmd_update ;;
    logs)       cmd_logs ;;
    status|ps)  cmd_status ;;
    backup)     cmd_backup ;;
    restore) shift; cmd_restore "$@" ;;
    demo)       cmd_demo ;;
    doctor|진단) cmd_doctor ;;
    *)
        cat <<'USAGE'
IT 자산관리 시스템 배포 도우미

  ./deploy.sh setup [포트]     최초 1회 - 설정 파일(.env) 생성 (기본 포트 8000)
  ./deploy.sh start            서비스 시작 (필요하면 이미지도 빌드)
  ./deploy.sh stop             서비스 중지
  ./deploy.sh restart          재시작
  ./deploy.sh update           최신 코드로 다시 빌드하고 재시작
  ./deploy.sh logs             실행 로그 보기
  ./deploy.sh status           상태 확인
  ./deploy.sh backup           데이터베이스 백업
  ./deploy.sh restore <파일>   백업 파일로 되돌리기
  ./deploy.sh demo             샘플 데이터 넣기 (처음 둘러볼 때만)
  ./deploy.sh doctor           접속이 안 될 때 원인 진단

처음이라면:  ./deploy.sh setup  →  ./deploy.sh start
USAGE
        exit 1
        ;;
esac
