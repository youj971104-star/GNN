"""애플리케이션 설정.

환경변수로 값을 덮어쓸 수 있으며, 지정하지 않으면 기본값을 사용한다.
"""

import os
import secrets
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BASE_DIR.parent
DATA_DIR = Path(os.getenv("ITAM_DATA_DIR", PROJECT_DIR / "data"))

# 세션 서명 키. 운영 환경에서는 반드시 ITAM_SECRET_KEY 를 고정 값으로 지정해야
# 서버를 재시작해도 로그인 세션이 유지된다.
SECRET_KEY = os.getenv("ITAM_SECRET_KEY") or secrets.token_hex(32)

# SQLite 파일 경로. PostgreSQL 등으로 옮길 때는 ITAM_DATABASE_URL 만 바꾸면 된다.
DATABASE_URL = os.getenv("ITAM_DATABASE_URL") or f"sqlite:///{DATA_DIR / 'itam.db'}"

# 최초 실행 시 자동 생성되는 관리자 계정
DEFAULT_ADMIN_USERNAME = os.getenv("ITAM_ADMIN_USERNAME", "admin")
DEFAULT_ADMIN_PASSWORD = os.getenv("ITAM_ADMIN_PASSWORD", "admin1234")

# 목록 화면 한 페이지당 행 수
PAGE_SIZE = int(os.getenv("ITAM_PAGE_SIZE", "20"))

# 로그인 유지 시간(초). 마지막으로 쓴 시점부터 세므로, 계속 쓰는 동안은 풀리지 않는다.
# 기본 30일. 폰으로 QR 라벨을 찍을 때마다 로그인하지 않게 넉넉히 둔다.
SESSION_MAX_AGE = int(os.getenv("ITAM_SESSION_MAX_AGE", str(30 * 24 * 60 * 60)))

# 로그인 화면에서 '로그인 상태 유지' 를 끄고 들어왔을 때의 유지 시간(초). 기본 12시간.
# 공용 PC 에서 잠깐 쓰고 나가는 경우를 위한 값이다.
SHORT_SESSION_MAX_AGE = int(os.getenv("ITAM_SHORT_SESSION_MAX_AGE", str(12 * 60 * 60)))

# 엑셀 업로드 최대 크기(바이트). 기본 10MB.
MAX_UPLOAD_BYTES = int(os.getenv("ITAM_MAX_UPLOAD_BYTES", str(10 * 1024 * 1024)))

# 세션 쿠키를 HTTPS 로만 전송할지 여부.
# 사내망 HTTP 로 쓰는 동안은 0, 도메인 + HTTPS 로 전환하면 1 로 바꾸면 된다.
HTTPS_ONLY = os.getenv("ITAM_HTTPS_ONLY", "0") == "1"

# 컨테이너 헬스체크 등에서 인증 없이 호출하는 상태 확인 경로
HEALTH_PATH = "/healthz"

# 라벨 인쇄 한 번에 담을 최대 자산 수 (너무 많으면 브라우저가 느려진다)
MAX_LABELS_PER_PRINT = int(os.getenv("ITAM_MAX_LABELS", "200"))

# --- 로그인 보호 ---------------------------------------------------------------
# 비밀번호를 이 횟수만큼 틀리면 계정을 잠시 잠근다 (무차별 대입 차단)
MAX_FAILED_LOGINS = int(os.getenv("ITAM_MAX_FAILED_LOGINS", "5"))
# 잠기는 시간(초). 기본 10분.
LOGIN_LOCK_SECONDS = int(os.getenv("ITAM_LOGIN_LOCK_SECONDS", "600"))
