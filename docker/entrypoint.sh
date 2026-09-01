#!/bin/sh
# 컨테이너 시작 스크립트
set -e

# 운영 환경에서 세션 키가 없으면 재시작할 때마다 로그인이 풀린다. 미리 막아 준다.
if [ -z "${ITAM_SECRET_KEY}" ]; then
    echo "════════════════════════════════════════════════════════════════"
    echo " [실행 중단] ITAM_SECRET_KEY 가 설정되지 않았습니다."
    echo ""
    echo " 이 값이 없으면 서버를 재시작할 때마다 모든 사용자의 로그인이 풀립니다."
    echo " 아래 명령으로 .env 파일을 만든 뒤 다시 실행해 주세요."
    echo ""
    echo "   ./deploy.sh setup"
    echo "════════════════════════════════════════════════════════════════"
    exit 1
fi

# 첫 인자가 옵션이 아니면(예: sh, python) 그대로 실행한다 - 백업·점검 작업용
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

echo "IT 자산관리 시스템을 시작합니다 (워커 ${ITAM_WORKERS}개, 포트 ${ITAM_PORT})"

# --proxy-headers 는 Nginx 뒤에 둘 때 원래 접속자 IP 와 https 여부를 올바로 읽기 위한 것이다.
exec uvicorn app.main:app \
    --host "${ITAM_HOST}" \
    --port "${ITAM_PORT}" \
    --workers "${ITAM_WORKERS}" \
    --proxy-headers \
    --forwarded-allow-ips "${ITAM_FORWARDED_ALLOW_IPS:-*}" \
    --access-log
