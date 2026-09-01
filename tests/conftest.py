"""테스트 공통 준비 - 임시 SQLite DB 와 로그인된 클라이언트."""

import os
import tempfile
from pathlib import Path

import pytest

# 앱 모듈을 임포트하기 전에 테스트용 설정을 넣어야 한다.
_TMP_DIR = tempfile.mkdtemp(prefix="itam-test-")
os.environ["ITAM_DATA_DIR"] = _TMP_DIR
os.environ["ITAM_DATABASE_URL"] = f"sqlite:///{Path(_TMP_DIR) / 'test.db'}"
os.environ["ITAM_SECRET_KEY"] = "test-secret-key"
os.environ["ITAM_ADMIN_PASSWORD"] = "admin1234"

from fastapi.testclient import TestClient  # noqa: E402

from app.database import Base, SessionLocal, engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models import Asset, Assignment, Employee, User  # noqa: E402
from app.security import hash_password  # noqa: E402


@pytest.fixture(autouse=True)
def clean_db():
    """테스트마다 빈 DB 로 시작한다."""
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)


@pytest.fixture
def db():
    with SessionLocal() as session:
        yield session


@pytest.fixture
def client():
    """lifespan 이 실행되어 기본 관리자 계정이 생성된 클라이언트."""
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def admin_client(client):
    response = client.post(
        "/login", data={"username": "admin", "password": "admin1234"}, follow_redirects=False
    )
    assert response.status_code == 303
    return client


@pytest.fixture
def viewer_client(client, db):
    db.add(
        User(
            username="viewer",
            name="조회자",
            role="USER",
            password_hash=hash_password("viewer1234"),
        )
    )
    db.commit()
    response = client.post(
        "/login", data={"username": "viewer", "password": "viewer1234"}, follow_redirects=False
    )
    assert response.status_code == 303
    return client


@pytest.fixture
def employee(db):
    emp = Employee(emp_no="E001", name="홍길동", department="개발팀", position="선임")
    db.add(emp)
    db.commit()
    db.refresh(emp)
    return emp


@pytest.fixture
def asset(db):
    item = Asset(asset_no="IT-2026-0001", name="테스트 노트북", category="NOTEBOOK", status="IN_STOCK")
    db.add(item)
    db.commit()
    db.refresh(item)
    return item
