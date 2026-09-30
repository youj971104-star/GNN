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
#   ./deploy.sh https <도메인> [이메일]   무료 인증서로 HTTPS 전환
#   ./deploy.sh https-off                 HTTP 로 되돌리기
#   ./deploy.sh duckdns <이름> <토큰>     DuckDNS 주소가 늘 이 서버를 가리키게

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

# .env 에 적어 둔 값 하나를 읽는다 (따옴표는 벗겨 준다)
env_value() {
    [ -f "$ENV_FILE" ] || return 0
    grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "\"'"
}

# HTTPS 로 전환했다면 도메인, 아니면 빈 값
DOMAIN="$(env_value ITAM_DOMAIN || true)"

# HTTPS 설정을 뺀 기본 명령 (되돌릴 때와 버전 확인에 쓴다)
DC_BASE="$DC"

# 전환한 뒤에는 start/stop/update 등 모든 명령이 HTTPS 설정을 함께 써야 한다
if [ -n "${DOMAIN:-}" ]; then
    DC="$DC -f docker-compose.yml -f docker-compose.https.yml --profile https"
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

# 공용 헬퍼(is_ipv4, cloud_public_ip)를 불러온다.
# 위에서 이미 스크립트가 있는 폴더로 이동했으므로 상대경로로 충분하다.
# shellcheck source=deploy/lib-common.sh
. ./deploy/lib-common.sh

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

# 목록 한 페이지 행 수 / 엑셀 업로드 최대 크기(바이트)
ITAM_PAGE_SIZE=20
ITAM_MAX_UPLOAD_BYTES=10485760

# 로그인 유지 시간(초). 마지막으로 쓴 시점부터 셉니다.
# 기본 30일 - 폰으로 QR 라벨을 찍을 때마다 다시 로그인하지 않도록 넉넉히 둡니다.
ITAM_SESSION_MAX_AGE=2592000
# 로그인 화면에서 '공용 PC' 를 체크했을 때의 유지 시간(초). 기본 12시간.
ITAM_SHORT_SESSION_MAX_AGE=43200

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
    if [ -n "${DOMAIN:-}" ] && [ ! -f deploy/nginx.conf ]; then
        fail "HTTPS 설정 파일(deploy/nginx.conf)이 없습니다."
        info "다시 만들려면:  ./deploy.sh https ${DOMAIN}"
        exit 1
    fi
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
            local public_ip; public_ip=$(cloud_public_ip)
            echo "  ── 접속 주소 ───────────────────────────────────"
            echo "     이 서버에서      : http://localhost:${port}"
            if [ -n "$public_ip" ]; then
                echo "     바깥에서         : http://${public_ip}:${port}"
                echo "     같은 사설망에서  : http://$(guess_host_ip):${port}"
            else
                echo "     다른 PC 에서     : http://$(guess_host_ip):${port}"
            fi
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

cmd_restart() { require_env; $DC restart "$SERVICE"; reload_nginx; ok "재시작했습니다."; }

# 예전 버전에서 만든 .env 를 새 설정에 맞춰 손봐 준다.
# 이 값이 예전 기본값(12시간) 그대로면, 폰에서 QR 을 찍을 때마다 로그인하게 된다.
migrate_env() {
    if grep -qE '^ITAM_SESSION_MAX_AGE=43200$' "$ENV_FILE" 2>/dev/null; then
        sed -i.bak 's/^ITAM_SESSION_MAX_AGE=43200$/ITAM_SESSION_MAX_AGE=2592000/' "$ENV_FILE"
        rm -f "${ENV_FILE}.bak"
        info "로그인 유지 시간을 12시간 → 30일로 바꿨습니다. (.env)"
    fi
    if ! grep -q '^ITAM_SHORT_SESSION_MAX_AGE=' "$ENV_FILE" 2>/dev/null; then
        printf '\n# 로그인 화면에서 \x27공용 PC\x27 를 체크했을 때의 유지 시간(초)\nITAM_SHORT_SESSION_MAX_AGE=43200\n' >> "$ENV_FILE"
    fi
}

cmd_update() {
    require_env
    migrate_env
    info "최신 코드로 다시 빌드합니다..."
    $DC up -d --build
    reload_nginx
    ok "업데이트를 마쳤습니다."
}

# app 컨테이너를 새로 만들면 주소가 바뀌어, Nginx 가 예전 주소를 붙들고 502 를 낸다.
# HTTPS 로 쓰는 중일 때만 설정을 다시 읽게 한다.
reload_nginx() {
    [ -z "${DOMAIN:-}" ] && return 0
    $DC exec -T nginx nginx -s reload >/dev/null 2>&1 || true
}

cmd_logs()   { $DC logs -f --tail=100 "$SERVICE"; }

cmd_status() {
    $DC ps
    echo ""
    local port; port=$(grep -E '^ITAM_PUBLIC_PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo 8000)
    if [ -n "${DOMAIN:-}" ]; then
        if curl -fsS --max-time 10 "https://${DOMAIN}/healthz" >/dev/null 2>&1; then
            ok "서비스 정상 (https://${DOMAIN})"
        else
            fail "HTTPS 주소에 응답이 없습니다. './deploy.sh logs' 로 확인해 주세요."
        fi
    elif curl -fsS "http://127.0.0.1:${port:-8000}/healthz" >/dev/null 2>&1; then
        local public_ip; public_ip=$(cloud_public_ip)
        ok "서비스 정상 (http://${public_ip:-$(guess_host_ip)}:${port:-8000})"
    else
        fail "서비스에 응답이 없습니다."
    fi
}

# 백업은 쌓이기만 하면 디스크를 채운다. 최근 것만 남긴다.
BACKUP_KEEP_DEFAULT=30

prune_backups() {
    local keep total removed=0
    keep=$(env_value ITAM_BACKUP_KEEP || true)
    keep="${keep:-$BACKUP_KEEP_DEFAULT}"
    case "$keep" in
        ''|*[!0-9]*) keep=$BACKUP_KEEP_DEFAULT ;;
    esac
    if [ "$keep" -lt 1 ]; then
        keep=1
    fi

    total=$(ls -1t backups/itam-*.db 2>/dev/null | wc -l)
    if [ "$total" -le "$keep" ]; then
        return 0
    fi

    while IFS= read -r file; do
        [ -n "$file" ] || continue
        rm -f "$file"
        removed=$((removed + 1))
    done < <(ls -1t backups/itam-*.db 2>/dev/null | tail -n +$((keep + 1)))

    info "오래된 백업 ${removed}개를 정리했습니다 (최근 ${keep}개 보관)"
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
    prune_backups
    info "보관 중인 백업: $(ls -1 backups/itam-*.db 2>/dev/null | wc -l)개"
}

cmd_autobackup() {
    require_env

    if [ "${1:-}" = "off" ]; then
        if remove_cron_line "deploy.sh backup"; then
            ok "자동 백업을 껐습니다."
        else
            fail "crontab 을 찾지 못했습니다."
        fi
        return 0
    fi

    # 기본 새벽 3시 17분. 정각은 다른 작업과 겹치기 쉬워 조금 비켜 둔다.
    local when="${1:-03:17}" hour minute
    if ! echo "$when" | grep -qE '^[0-2][0-9]:[0-5][0-9]$'; then
        fail "시각은 HH:MM 형식으로 넣어 주세요.  예)  ./deploy.sh autobackup 03:17"
        exit 1
    fi
    hour=${when%%:*}
    minute=${when##*:}
    if [ "$((10#$hour))" -gt 23 ]; then
        fail "시각이 올바르지 않습니다: $when"
        exit 1
    fi

    mkdir -p backups
    if ! install_cron_line "deploy.sh backup" \
        "$((10#$minute)) $((10#$hour)) * * * cd $PWD && ./deploy.sh backup >> backups/backup.log 2>&1"; then
        fail "crontab 을 찾지 못해 자동 백업을 등록하지 못했습니다."
        info "대신 './deploy.sh backup' 을 주기적으로 직접 실행해 주세요."
        exit 1
    fi

    local keep; keep=$(env_value ITAM_BACKUP_KEEP || true)
    ok "매일 ${when} 에 자동으로 백업합니다 (최근 ${keep:-$BACKUP_KEEP_DEFAULT}개 보관)"
    info "기록: backups/backup.log · 끄려면 ./deploy.sh autobackup off"
    info "백업 파일은 이 서버 안에 있습니다. 가끔 다른 곳으로도 내려받아 두세요:"
    info "  scp -i <키파일> ubuntu@<서버IP>:$PWD/backups/*.db ."
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
    local public_ip; public_ip=$(cloud_public_ip)
    echo "  ── 접속 주소 ───────────────────────────────────"
    echo "     이 서버에서      : http://localhost:${port}"
    if [ -n "$public_ip" ]; then
        echo "     바깥에서         : http://${public_ip}:${port}"
        echo "     같은 사설망에서  : http://$(guess_host_ip):${port}"
    else
        echo "     다른 PC 에서     : http://$(guess_host_ip):${port}"
    fi
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

# ─────────────────────────────────────────────────────────────
#  도메인 + HTTPS (Let's Encrypt 무료 인증서)
# ─────────────────────────────────────────────────────────────

CERT_DIR="deploy/certs"
WEBROOT="deploy/certbot-webroot"
CERTBOT_IMAGE="certbot/certbot:latest"

# certbot 컨테이너가 인증서 폴더를 root 소유로 만든다.
# 지우거나 손볼 때도 컨테이너 안에서 root 로 해야 sudo 가 필요 없다.
certbot_run() {
    docker run --rm \
        -v "$PWD/${CERT_DIR}:/etc/letsencrypt" \
        -v "$PWD/${WEBROOT}:/var/www/certbot" \
        "$CERTBOT_IMAGE" "$@"
}

certbot_shell() {
    docker run --rm --entrypoint sh \
        -v "$PWD/${CERT_DIR}:/etc/letsencrypt" \
        -v "$PWD/${WEBROOT}:/var/www/certbot" \
        "$CERTBOT_IMAGE" -c "$1"
}

# 이 서버 방화벽에 포트를 연다 (오라클 콘솔의 수신 규칙은 따로 열어야 한다)
open_firewall_port() {
    local port="$1" sudo_cmd=""
    [ "$(id -u)" -ne 0 ] && sudo_cmd="sudo"

    if command -v firewall-cmd >/dev/null 2>&1 && $sudo_cmd firewall-cmd --state >/dev/null 2>&1; then
        $sudo_cmd firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null
        $sudo_cmd firewall-cmd --reload >/dev/null
        ok "방화벽에 ${port}/tcp 를 열었습니다"
    elif command -v iptables >/dev/null 2>&1; then
        # 검사(-C)와 추가(-I)의 규칙 내용이 완전히 같아야 중복해서 쌓이지 않는다
        local rule=(-p tcp --dport "$port" -m state --state NEW,ESTABLISHED -j ACCEPT)
        if $sudo_cmd iptables -C INPUT "${rule[@]}" 2>/dev/null; then
            info "방화벽에 ${port} 번이 이미 열려 있습니다"
        else
            $sudo_cmd iptables -I INPUT 1 "${rule[@]}"
            ok "방화벽에 ${port}/tcp 를 열었습니다"
        fi
        if command -v netfilter-persistent >/dev/null 2>&1; then
            $sudo_cmd netfilter-persistent save >/dev/null 2>&1 || true
        elif [ -d /etc/iptables ]; then
            $sudo_cmd sh -c "iptables-save > /etc/iptables/rules.v4" 2>/dev/null || true
        fi
    else
        info "방화벽 도구를 찾지 못했습니다. ${port} 번이 열려 있는지 직접 확인해 주세요."
    fi
}

# 크론에 줄 하나를 넣는다. 같은 표시(marker)가 붙은 예전 줄은 지우고 새로 넣어,
# 여러 번 실행해도 줄이 쌓이지 않는다.
#
# grep 은 걸러낼 줄이 하나도 없으면 실패로 끝난다. || true 를 빼면 크론이 비어
# 있는 서버에서 등록이 조용히 건너뛰어진다.
install_cron_line() {
    local marker="$1" line="$2"
    if ! command -v crontab >/dev/null 2>&1; then
        return 1
    fi
    local current
    current=$(crontab -l 2>/dev/null | grep -v "$marker" || true)
    printf '%s\n%s\n' "$current" "$line" | grep -v '^$' | crontab -
}

remove_cron_line() {
    local marker="$1"
    if ! command -v crontab >/dev/null 2>&1; then
        return 1
    fi
    local current
    current=$(crontab -l 2>/dev/null | grep -v "$marker" || true)
    printf '%s\n' "$current" | grep -v '^$' | crontab - 2>/dev/null || crontab -r 2>/dev/null || true
}

# .env 값 하나를 더하거나 고친다
set_env_value() {
    local key="$1" value="$2"
    if grep -qE "^${key}=" "$ENV_FILE"; then
        sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
    else
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
    fi
}

# compose 가 !override 를 이해하는지 (2.24 이상)
require_compose_version() {
    local version
    version=$($DC_BASE version --short 2>/dev/null | tr -d 'v' || echo "")
    [ -z "$version" ] && return 0

    local major minor
    major=${version%%.*}
    minor=$(echo "$version" | cut -d. -f2)
    if [ "${major:-0}" -gt 2 ] || { [ "${major:-0}" -eq 2 ] && [ "${minor:-0}" -ge 24 ]; }; then
        return 0
    fi

    fail "Docker Compose 가 너무 오래된 버전입니다 (현재 ${version}, 2.24 이상 필요)"
    info "다음 명령으로 올린 뒤 다시 실행해 주세요:"
    info "  curl -fsSL https://get.docker.com | sudo sh"
    exit 1
}

cmd_https() {
    require_env
    local domain="${1:-}" email="${2:-}"

    if [ -z "$domain" ]; then
        fail "도메인을 지정해 주세요.  예)  ./deploy.sh https itam.example.duckdns.org 담당자@회사.com"
        exit 1
    fi
    if ! echo "$domain" | grep -qE '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$'; then
        fail "도메인 형식이 올바르지 않습니다: $domain"
        exit 1
    fi
    require_compose_version

    echo ""
    info "도메인      : $domain"
    info "인증서      : Let's Encrypt (무료, 90일마다 자동 갱신)"
    echo ""

    # ── 1. 도메인이 이 서버를 가리키는지 ──
    local resolved public
    resolved=$(getent hosts "$domain" 2>/dev/null | awk '{print $1}' | head -1 || true)
    public=$(cloud_public_ip || true)
    if [ -z "$resolved" ]; then
        fail "도메인 '$domain' 이 아직 어떤 IP 도 가리키지 않습니다."
        info "DNS 에 이 서버 주소(${public:-<서버 공인IP>})를 등록한 뒤 다시 실행해 주세요."
        info "DuckDNS 를 쓴다면: ./deploy.sh duckdns <이름> <토큰>"
        exit 1
    fi
    if [ -n "$public" ] && [ "$resolved" != "$public" ]; then
        fail "도메인이 다른 곳을 가리키고 있습니다."
        info "  $domain → $resolved"
        info "  이 서버   → $public"
        info "DNS 를 고치고 몇 분 기다린 뒤 다시 실행해 주세요."
        exit 1
    fi
    ok "도메인이 이 서버(${resolved})를 가리킵니다"

    # ── 2. 80 / 443 열기 ──
    open_firewall_port 80
    open_firewall_port 443

    # ── 3. 설정 기록과 Nginx 설정 만들기 ──
    mkdir -p "$CERT_DIR" "$WEBROOT/.well-known/acme-challenge"
    sed "s|@@DOMAIN@@|${domain}|g" deploy/nginx.conf.template > deploy/nginx.conf
    set_env_value ITAM_DOMAIN "$domain"
    set_env_value ITAM_HTTPS_ONLY 1
    ok "Nginx 설정을 만들었습니다 (deploy/nginx.conf)"

    # Nginx 는 인증서 파일이 없으면 아예 뜨지 않는다.
    # 먼저 임시 인증서를 만들어 띄운 뒤, 그 위에서 진짜 인증서를 받는다.
    if [ ! -s "${CERT_DIR}/live/${domain}/fullchain.pem" ]; then
        certbot_shell "mkdir -p /etc/letsencrypt/live/${domain} && \
            openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
            -keyout /etc/letsencrypt/live/${domain}/privkey.pem \
            -out /etc/letsencrypt/live/${domain}/fullchain.pem \
            -subj '/CN=${domain}' >/dev/null 2>&1"
        info "임시 인증서를 만들었습니다 (곧 진짜 인증서로 바뀝니다)"
    fi

    local DC_HTTPS="$DC_BASE -f docker-compose.yml -f docker-compose.https.yml --profile https"

    info "서비스를 HTTPS 구성으로 다시 시작합니다..."
    $DC_HTTPS up -d --build
    sleep 5

    # ── 4. 80 번이 바깥에서 실제로 열렸는지 먼저 확인한다 ──
    # 여기서 막혀 있으면 인증서 발급이 실패하고, 실패 횟수 제한에 걸린다.
    local probe="itam-$(date +%s)"
    echo "$probe" > "${WEBROOT}/.well-known/acme-challenge/${probe}"
    if ! curl -fsS --max-time 15 "http://${domain}/.well-known/acme-challenge/${probe}" 2>/dev/null | grep -q "$probe"; then
        rm -f "${WEBROOT}/.well-known/acme-challenge/${probe}"
        echo ""
        fail "바깥에서 80 번 포트로 들어올 수 없습니다. 인증서를 받을 수 없습니다."
        echo ""
        info "오라클 클라우드 콘솔에서 수신 규칙을 추가해 주세요:"
        info "  네트워킹 > 가상 클라우드 네트워크 > 서브넷 > 보안 목록 > 수신 규칙 추가"
        info "  소스 0.0.0.0/0 · 대상 포트 80"
        info "  같은 방법으로 443 번도 열어 주세요."
        echo ""
        info "열고 나서 다시 실행하시면 이어서 진행됩니다:  ./deploy.sh https $domain $email"
        exit 1
    fi
    rm -f "${WEBROOT}/.well-known/acme-challenge/${probe}"
    ok "바깥에서 80 번으로 들어올 수 있습니다"

    # ── 5. 진짜 인증서 받기 ──
    # 임시 인증서를 지워야 certbot 이 새로 발급한다
    certbot_shell "rm -rf /etc/letsencrypt/live/${domain} /etc/letsencrypt/archive/${domain} \
        /etc/letsencrypt/renewal/${domain}.conf"

    local email_args=(--register-unsafely-without-email)
    [ -n "$email" ] && email_args=(--email "$email")
    local staging_args=()
    [ "${ITAM_LE_STAGING:-0}" = "1" ] && staging_args=(--staging)

    info "Let's Encrypt 인증서를 받는 중..."
    if ! certbot_run certonly --webroot -w /var/www/certbot \
            -d "$domain" "${email_args[@]}" ${staging_args[@]+"${staging_args[@]}"} \
            --agree-tos --no-eff-email --non-interactive; then
        echo ""
        fail "인증서 발급에 실패했습니다. 위 메시지를 확인해 주세요."
        info "같은 도메인으로 짧은 시간에 여러 번 실패하면 한 시간쯤 기다려야 합니다."
        info "서비스는 임시 인증서로 계속 떠 있습니다 (브라우저 경고가 뜹니다)."
        exit 1
    fi

    $DC_HTTPS exec -T nginx nginx -s reload >/dev/null 2>&1 || $DC_HTTPS restart nginx >/dev/null
    sleep 3

    # ── 6. 확인 ──
    echo ""
    if curl -fsS --max-time 15 "https://${domain}/healthz" >/dev/null 2>&1; then
        ok "HTTPS 로 접속됩니다"
    else
        fail "아직 HTTPS 응답이 없습니다. './deploy.sh logs' 로 확인해 주세요."
    fi

    echo ""
    echo "  ──────────────────────────────────────────────"
    echo "     접속 주소 : https://${domain}"
    echo "  ──────────────────────────────────────────────"
    info "인증서는 90일마다 자동으로 갱신됩니다 (certbot 컨테이너)."
    info "예전 주소(http://<서버IP>:$(env_value ITAM_PUBLIC_PORT || echo 8000))로 들어와도 이 주소로 넘어갑니다."
    info "이미 붙여 둔 QR 라벨도 그대로 쓸 수 있습니다."
    info "쿠키가 HTTPS 전용으로 바뀌므로 한 번은 다시 로그인해야 합니다."
    echo ""
}

cmd_https_off() {
    require_env
    local domain; domain="$(env_value ITAM_DOMAIN || true)"
    if [ -z "$domain" ]; then
        info "HTTPS 로 전환된 상태가 아닙니다."
        exit 0
    fi

    info "HTTP 로 되돌립니다..."
    $DC down
    set_env_value ITAM_HTTPS_ONLY 0
    sed -i.bak '/^ITAM_DOMAIN=/d' "$ENV_FILE" && rm -f "${ENV_FILE}.bak"

    $DC_BASE up -d
    ok "되돌렸습니다. http://<서버IP>:$(env_value ITAM_PUBLIC_PORT || echo 8000) 로 접속하세요."
    info "인증서는 ${CERT_DIR} 에 남아 있어, 다시 켤 때 그대로 쓰입니다."
}

cmd_duckdns() {
    require_env
    local name="${1:-}" token="${2:-}"
    if [ -z "$name" ] || [ -z "$token" ]; then
        fail "사용법:  ./deploy.sh duckdns <이름> <토큰>"
        info "https://www.duckdns.org 에 로그인하면 이름과 토큰을 받을 수 있습니다."
        info "이름이 'ourcompany' 라면 주소는 ourcompany.duckdns.org 가 됩니다."
        exit 1
    fi

    set_env_value ITAM_DUCKDNS_NAME "$name"
    set_env_value ITAM_DUCKDNS_TOKEN "$token"
    chmod 600 "$ENV_FILE"

    if ! ./deploy/duckdns-update.sh; then
        fail "DuckDNS 갱신에 실패했습니다. 이름과 토큰을 확인해 주세요."
        exit 1
    fi

    # 공인 IP 가 바뀌어도 주소가 따라오도록 5분마다 갱신한다
    if install_cron_line "duckdns-update.sh" \
        "*/5 * * * * cd $PWD && ./deploy/duckdns-update.sh >/dev/null 2>&1"; then
        ok "5분마다 주소를 자동으로 맞춥니다 (crontab 등록 완료)"
    else
        info "crontab 을 찾지 못해 자동 갱신은 등록하지 못했습니다."
        info "공인 IP 가 바뀌면 './deploy/duckdns-update.sh' 를 다시 실행해 주세요."
    fi

    ok "${name}.duckdns.org 가 이 서버를 가리키도록 설정했습니다"
    info "이제 HTTPS 로 전환할 수 있습니다:"
    info "  ./deploy.sh https ${name}.duckdns.org 담당자@회사.com"
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
    autobackup) shift; cmd_autobackup "$@" ;;
    restore) shift; cmd_restore "$@" ;;
    demo)       cmd_demo ;;
    doctor|진단) cmd_doctor ;;
    https)      shift; cmd_https "$@" ;;
    https-off)  cmd_https_off ;;
    duckdns)    shift; cmd_duckdns "$@" ;;
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
  ./deploy.sh backup           데이터베이스 백업 (지금 한 번)
  ./deploy.sh autobackup [HH:MM]  매일 자동 백업 (기본 03:17, 끄기: autobackup off)
  ./deploy.sh restore <파일>   백업 파일로 되돌리기
  ./deploy.sh demo             샘플 데이터 넣기 (처음 둘러볼 때만)
  ./deploy.sh doctor           접속이 안 될 때 원인 진단

  ── 도메인 + HTTPS (무료) ──
  ./deploy.sh duckdns <이름> <토큰>     무료 주소(DuckDNS)가 이 서버를 가리키게
  ./deploy.sh https <도메인> [이메일]   무료 인증서를 받아 HTTPS 로 전환
  ./deploy.sh https-off                 HTTP 로 되돌리기

처음이라면:  ./deploy.sh setup  →  ./deploy.sh start
HTTPS 로 바꾸려면 deploy/README-HTTPS.md 를 보세요.
USAGE
        exit 1
        ;;
esac
