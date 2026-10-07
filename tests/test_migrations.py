"""기존 DB 에 새 컬럼을 덧붙이는 스키마 이전 테스트.

운영 중인 서버의 데이터가 걸린 부분이라, 데이터 보존과 멱등성을 함께 확인한다.
"""

import sqlite3

from sqlalchemy import create_engine, inspect, text

from app.migrations import apply_pending_migrations, pending_columns

# 감가상각 컬럼이 없던 시절의 assets 테이블
OLD_ASSETS_SCHEMA = """
CREATE TABLE assets (
  id INTEGER PRIMARY KEY,
  asset_no VARCHAR(50) UNIQUE,
  name VARCHAR(120),
  category VARCHAR(30),
  status VARCHAR(20),
  manufacturer VARCHAR(60),
  model_name VARCHAR(120),
  serial_no VARCHAR(120),
  spec TEXT,
  location VARCHAR(80),
  supplier VARCHAR(80),
  purchase_date DATE,
  purchase_price NUMERIC(14,2),
  warranty_until DATE,
  license_key VARCHAR(255),
  note TEXT,
  holder_id INTEGER,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
);
"""


def _old_database(tmp_path):
    """새 컬럼이 없는 예전 DB 를 만들고 자산 한 건을 넣는다."""
    path = tmp_path / "old.db"
    con = sqlite3.connect(path)
    con.executescript(OLD_ASSETS_SCHEMA)
    con.execute(
        "INSERT INTO assets (asset_no, name, category, status, purchase_price,"
        " created_at, updated_at) VALUES (?,?,?,?,?,?,?)",
        ("IT-OLD-1", "기존 자산", "NOTEBOOK", "IN_USE", 1_500_000,
         "2026-01-01 00:00:00", "2026-01-01 00:00:00"),
    )
    con.commit()
    con.close()
    return create_engine(f"sqlite:///{path}")


def test_빠진_컬럼을_찾아낸다(tmp_path):
    engine = _old_database(tmp_path)
    missing = {name for table, column in pending_columns(engine)
               if table == "assets" for name in [column.name]}

    assert "depreciation_method" in missing
    assert "useful_life_years" in missing
    assert "salvage_value" in missing
    assert "asset_no" not in missing  # 이미 있는 컬럼은 대상이 아니다


def test_컬럼을_추가해도_기존_데이터가_남는다(tmp_path):
    engine = _old_database(tmp_path)
    apply_pending_migrations(engine)

    columns = {c["name"] for c in inspect(engine).get_columns("assets")}
    assert {"depreciation_method", "useful_life_years", "salvage_value"} <= columns

    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT asset_no, name, purchase_price, depreciation_method FROM assets")
        ).one()
    assert row.asset_no == "IT-OLD-1"
    assert row.name == "기존 자산"
    assert float(row.purchase_price) == 1_500_000
    assert row.depreciation_method is None  # 새 컬럼은 비어 있다


def test_여러_번_실행해도_안전하다(tmp_path):
    engine = _old_database(tmp_path)

    first = apply_pending_migrations(engine)
    assert first, "첫 실행에서는 컬럼이 추가되어야 한다"

    second = apply_pending_migrations(engine)
    assert second == [], "두 번째 실행에서는 아무것도 하지 않아야 한다"


def test_이미_최신인_DB_는_건드리지_않는다(tmp_path):
    """앱이 만든 최신 스키마에는 추가할 컬럼이 없어야 한다."""
    from app.database import Base

    path = tmp_path / "new.db"
    engine = create_engine(f"sqlite:///{path}")
    Base.metadata.create_all(bind=engine)

    assert pending_columns(engine) == []
    assert apply_pending_migrations(engine) == []


def test_없는_테이블은_건너뛴다(tmp_path):
    """테이블 자체가 없으면 create_all 이 만들므로 이전 대상이 아니다."""
    path = tmp_path / "empty.db"
    engine = create_engine(f"sqlite:///{path}")
    with engine.begin() as conn:
        conn.execute(text("CREATE TABLE dummy (id INTEGER PRIMARY KEY)"))

    assert pending_columns(engine) == []


OLD_USERS_SCHEMA = """
CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  username VARCHAR(50) UNIQUE,
  password_hash VARCHAR(255),
  name VARCHAR(50),
  role VARCHAR(20),
  is_active BOOLEAN,
  created_at DATETIME NOT NULL,
  last_login_at DATETIME
);
"""


def _old_users_database(tmp_path):
    """2단계 인증 컬럼이 없던 시절의 users 테이블."""
    path = tmp_path / "old_users.db"
    con = sqlite3.connect(path)
    con.executescript(OLD_USERS_SCHEMA)
    con.execute(
        "INSERT INTO users (username, password_hash, name, role, is_active, created_at)"
        " VALUES (?,?,?,?,?,?)",
        ("admin", "x", "기존관리자", "ADMIN", 1, "2026-01-01 00:00:00"),
    )
    con.commit()
    con.close()
    return create_engine(f"sqlite:///{path}")


def test_컬럼을_덧붙일_때_기존_행에_기본값을_채운다(tmp_path):
    """빈 값으로 두면 '꺼짐'을 찾는 조건 검색에서 기존 행이 빠진다."""
    engine = _old_users_database(tmp_path)
    apply_pending_migrations(engine)

    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT totp_enabled, failed_logins, totp_secret FROM users")
        ).one()

    assert row.totp_enabled == 0        # False 로 채워진다 (NULL 이 아니다)
    assert row.failed_logins == 0
    assert row.totp_secret is None      # 기본값이 없는 컬럼은 비워 둔다

    # 조건 검색에 제대로 걸리는지
    with engine.connect() as conn:
        found = conn.execute(
            text("SELECT COUNT(*) FROM users WHERE totp_enabled = 0")
        ).scalar()
    assert found == 1


def test_기존_계정은_2단계_인증이_꺼진_채로_이어진다(tmp_path):
    """이미 쓰던 계정이 갑자기 로그인 못 하게 되면 안 된다."""
    engine = _old_users_database(tmp_path)
    apply_pending_migrations(engine)

    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT username, name, role, totp_enabled FROM users")
        ).one()

    assert row.username == "admin"
    assert row.name == "기존관리자"
    assert row.role == "ADMIN"
    assert not row.totp_enabled
