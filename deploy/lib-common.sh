#!/usr/bin/env bash
# deploy.sh 와 oracle-setup.sh 가 함께 쓰는 헬퍼.
# 이 파일은 직접 실행하지 않고 source 로 불러 쓴다.

# 받은 값이 진짜 IPv4 주소인지 확인한다.
# 프록시나 오류 페이지가 엉뚱한 문자열을 돌려줄 수 있어 형식을 꼭 검사한다.
is_ipv4() {
    local value="${1:-}" part
    case "$value" in
        *[!0-9.]*|"") return 1 ;;
    esac
    local IFS=.
    # shellcheck disable=SC2086
    set -- $value
    [ "$#" -eq 4 ] || return 1
    for part in "$@"; do
        [ -n "$part" ] || return 1
        [ "$part" -le 255 ] 2>/dev/null || return 1
    done
    return 0
}

# 이 서버의 공인 IP. 알아내지 못하면 빈 값을 돌려준다.
#
# 오라클은 공인 IP 를 랜카드에 붙이지 않고 NAT 로 연결한다. 서버 안에서는
# 사설 IP(10.0.0.x)만 보이고, 메타데이터(/opc/v2/vnics/)에도 publicIp 항목이
# 아예 없다. 그래서 바깥 서비스에 "내가 어떤 주소로 보이느냐"고 되물어 알아낸다.
cloud_public_ip() {
    local ip="" token="" service

    # AWS EC2 는 메타데이터에 공인 IP 가 들어 있어 바깥에 묻지 않아도 된다.
    # 메타데이터 주소는 프록시를 거치면 안 되므로 --noproxy 를 쓴다.
    token=$(curl -s --max-time 2 --noproxy '*' -X PUT \
                http://169.254.169.254/latest/api/token \
                -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null) || true
    if [ -n "$token" ]; then
        ip=$(curl -s --max-time 2 --noproxy '*' \
                -H "X-aws-ec2-metadata-token: $token" \
                http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null) || true
        if is_ipv4 "$ip"; then echo "$ip"; return; fi
    fi

    # 그 외(오라클 포함)는 바깥 서비스에 되묻는다.
    # 한 곳이 막혀 있을 수 있어 순서대로 시도한다.
    for service in https://checkip.amazonaws.com https://api.ipify.org https://ifconfig.me/ip; do
        ip=$(curl -s --max-time 3 "$service" 2>/dev/null | tr -d '[:space:]') || true
        if is_ipv4 "$ip"; then echo "$ip"; return; fi
    done

    echo ""
}
