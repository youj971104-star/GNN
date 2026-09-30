#!/usr/bin/env bash
# DuckDNS 주소가 늘 이 서버를 가리키게 한다.
#
# 오라클 무료 VM 의 공인 IP 는 인스턴스를 멈췄다 켜면 바뀔 수 있다.
# 바뀌어도 도메인이 따라오도록 5분마다 이 스크립트를 실행한다.
# (등록:  ./deploy.sh duckdns <이름> <토큰>)
#
# 이름과 토큰은 .env 에 들어 있다. 이 파일에는 비밀 값을 적지 않는다.

set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
    echo "[오류] .env 파일이 없습니다. './deploy.sh setup' 을 먼저 실행해 주세요." >&2
    exit 1
fi

NAME=$(grep -E '^ITAM_DUCKDNS_NAME=' .env | tail -1 | cut -d= -f2- | tr -d "\"'")
TOKEN=$(grep -E '^ITAM_DUCKDNS_TOKEN=' .env | tail -1 | cut -d= -f2- | tr -d "\"'")

if [ -z "${NAME:-}" ] || [ -z "${TOKEN:-}" ]; then
    echo "[오류] DuckDNS 이름과 토큰이 없습니다. './deploy.sh duckdns <이름> <토큰>' 을 실행해 주세요." >&2
    exit 1
fi

# ip 를 비워 두면 DuckDNS 가 요청을 보낸 쪽의 IP 를 그대로 쓴다.
# 서버가 NAT 뒤에 있어도(오라클처럼) 바깥에서 보이는 주소로 맞춰진다.
RESULT=$(curl -fsS --max-time 20 \
    "https://www.duckdns.org/update?domains=${NAME}&token=${TOKEN}&ip=" || echo "NETWORK_ERROR")

if [ "$RESULT" = "OK" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S')  ${NAME}.duckdns.org 갱신 완료"
    exit 0
fi

echo "$(date '+%Y-%m-%d %H:%M:%S')  갱신 실패: ${RESULT}" >&2
exit 1
