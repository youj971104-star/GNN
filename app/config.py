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

# 세션 유지 시간(초). 기본 12시간.
SESSION_MAX_AGE = int(os.getenv("ITAM_SESSION_MAX_AGE", str(12 * 60 * 60)))

# 엑셀 업로드 최대 크기(바이트). 기본 10MB.
MAX_UPLOAD_BYTES = int(os.getenv("ITAM_MAX_UPLOAD_BYTES", str(10 * 1024 * 1024)))
