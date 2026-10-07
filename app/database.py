"""데이터베이스 연결과 세션 관리."""

from collections.abc import Iterator

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app import config, dbcrypt


def build_engine(url: str, *, key: str | None = None):
    """DB 엔진을 만든다. key 가 있으면 SQLCipher 로 파일을 암호화해서 쓴다."""
    connect_args = {}
    options = {}
    is_sqlite = url.startswith("sqlite")

    if is_sqlite:
        # SQLite 파일은 요청 스레드가 달라도 같은 커넥션을 쓸 수 있어야 한다.
        connect_args["check_same_thread"] = False
        if key:
            dbcrypt.validate_key(key)
            # sqlite3 와 쓰는 법이 같은 SQLCipher 드라이버로 바꿔 끼운다
            options["module"] = dbcrypt.driver()

    new_engine = create_engine(url, connect_args=connect_args, future=True, **options)

    if is_sqlite:

        @event.listens_for(new_engine, "connect")
        def _tune_sqlite(dbapi_connection, connection_record):
            """SQLite 커넥션마다 필요한 설정을 켠다."""
            cursor = dbapi_connection.cursor()
            if key:
                # 암호화된 파일은 다른 어떤 명령보다 먼저 키를 넣어야 읽힌다.
                cursor.execute(dbcrypt.key_pragma(key))
            # SQLite 는 기본적으로 외래키 제약을 끄고 동작한다.
            cursor.execute("PRAGMA foreign_keys=ON")
            # WAL 모드라야 여러 워커 프로세스가 동시에 읽고 쓸 때 서로 막지 않는다.
            cursor.execute("PRAGMA journal_mode=WAL")
            # 잠깐 잠겨 있으면 바로 실패하지 말고 5초까지 기다린다.
            cursor.execute("PRAGMA busy_timeout=5000")
            cursor.close()

    return new_engine


if config.DATABASE_URL.startswith("sqlite"):
    config.DATA_DIR.mkdir(parents=True, exist_ok=True)

engine = build_engine(config.DATABASE_URL, key=config.DB_KEY)


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
    """테이블이 없으면 만들고, 기존 테이블에 빠진 컬럼이 있으면 덧붙인다."""
    from app import models  # noqa: F401  (모델 등록을 위해 임포트한다)
    from app.backup import SQLITE_PREFIX, sqlite_path

    # 키 설정과 파일 상태가 어긋나 있으면, 알아보기 힘든 오류 대신 할 일을 알려 준다
    if config.DATABASE_URL.startswith(SQLITE_PREFIX):
        dbcrypt.check_database_file(sqlite_path(), config.DB_KEY)

    Base.metadata.create_all(bind=engine)

    # 이미 쓰고 있던 DB 에 새 컬럼이 생겼을 때를 위한 처리.
    # 기존 데이터는 그대로 두고 컬럼만 추가한다.
    from app.migrations import apply_pending_migrations

    apply_pending_migrations(engine)
