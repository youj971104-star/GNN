"""데이터베이스 연결과 세션 관리."""

from collections.abc import Iterator

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app import config

_connect_args = {}
if config.DATABASE_URL.startswith("sqlite"):
    # SQLite 파일은 요청 스레드가 달라도 같은 커넥션을 쓸 수 있어야 한다.
    _connect_args["check_same_thread"] = False
    config.DATA_DIR.mkdir(parents=True, exist_ok=True)

engine = create_engine(config.DATABASE_URL, connect_args=_connect_args, future=True)

if config.DATABASE_URL.startswith("sqlite"):

    @event.listens_for(engine, "connect")
    def _enable_sqlite_foreign_keys(dbapi_connection, connection_record):
        """SQLite 는 기본적으로 외래키 제약을 끄고 동작하므로 켜 준다."""
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    """모든 모델의 공통 베이스."""


def get_db() -> Iterator[Session]:
    """요청 하나당 DB 세션 하나를 열고 닫는다 (FastAPI 의존성)."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    """테이블이 없으면 만든다."""
    from app import models  # noqa: F401  (모델 등록을 위해 임포트한다)

    Base.metadata.create_all(bind=engine)
