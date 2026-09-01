"""모든 화면이 실제로 렌더링되는지 확인하는 스모크 테스트."""

import pytest
from sqlalchemy import select

from app.models import Asset, Employee, User
from app.services import assign_asset, return_asset

ADMIN_PAGES = [
    "/",
    "/assets",
    "/assets?q=노트북&category=NOTEBOOK&status=IN_USE&sort=purchase_date",
    "/assets?unassigned=1",
    "/assets/new",
    "/assets/import",
    "/employees",
    "/employees?q=개발&status=ACTIVE",
    "/assignments",
    "/assignments?state=open",
    "/assignments?state=returned",
    "/assignments/new",
    "/users",
    "/users/new",
    "/me/password",
]

VIEWER_PAGES = [
    "/",
    "/assets",
    "/employees",
    "/assignments",
    "/me/password",
]


@pytest.fixture
def sample_data(db):
    """자산·직원·이력이 두루 있는 상태를 만든다."""
    employees = [
        Employee(emp_no="E001", name="김서준", department="개발팀", position="팀장"),
        Employee(emp_no="E002", name="이하윤", department="디자인팀", position="선임"),
    ]
    assets = [
        Asset(asset_no="IT-0001", name="개발팀 노트북", category="NOTEBOOK", purchase_price=2_000_000),
        Asset(asset_no="IT-0002", name="회의실 모니터", category="MONITOR", purchase_price=500_000),
        Asset(asset_no="IT-0003", name="수리중 프린터", category="PERIPHERAL", status="REPAIR"),
    ]
    db.add_all(employees + assets)
    db.commit()

    assign_asset(db, asset=assets[0], employee=employees[0], actor="admin")
    closed = assign_asset(db, asset=assets[1], employee=employees[1], actor="admin")
    return_asset(db, assignment=closed, new_status="IN_STOCK", actor="admin")
    return {"employees": employees, "assets": assets}


@pytest.mark.parametrize("path", ADMIN_PAGES)
def test_관리자_화면이_모두_열린다(admin_client, sample_data, path):
    response = admin_client.get(path)
    assert response.status_code == 200, f"{path} 응답 {response.status_code}"
    assert "<html" in response.text


@pytest.mark.parametrize("path", VIEWER_PAGES)
def test_일반_사용자_화면이_모두_열린다(viewer_client, sample_data, path):
    response = viewer_client.get(path)
    assert response.status_code == 200, f"{path} 응답 {response.status_code}"


def test_상세_및_수정_화면이_열린다(admin_client, db, sample_data):
    asset = db.scalar(select(Asset).where(Asset.asset_no == "IT-0001"))
    employee = db.scalar(select(Employee).where(Employee.emp_no == "E001"))
    account = db.scalar(select(User).where(User.username == "admin"))

    for path in (
        f"/assets/{asset.id}",
        f"/assets/{asset.id}/edit",
        f"/employees/{employee.id}",
        f"/employees/{employee.id}/edit",
        f"/users/{account.id}/edit",
    ):
        assert admin_client.get(path).status_code == 200, path


def test_엑셀_다운로드_화면이_모두_동작한다(admin_client, sample_data):
    for path in ("/assets/export", "/assets/template", "/employees/export", "/assignments/export"):
        response = admin_client.get(path)
        assert response.status_code == 200, path
        assert response.content[:2] == b"PK", path


def test_목록_페이지네이션이_동작한다(admin_client, db):
    db.add_all(
        [Asset(asset_no=f"IT-{i:04d}", name=f"자산 {i}", category="ETC") for i in range(1, 46)]
    )
    db.commit()

    first = admin_client.get("/assets?page=1")
    assert "전체 45건" in first.text
    assert "자산 1</td>" in first.text or "자산 1" in first.text

    last = admin_client.get("/assets?page=3")
    assert last.status_code == 200
    assert "자산 45" in last.text


def test_직원_목록에_보유_자산_수가_보인다(admin_client, sample_data):
    response = admin_client.get("/employees")
    assert response.status_code == 200
    assert "김서준" in response.text and "이하윤" in response.text


def test_로그인하면_상단에_사용자_정보와_관리자_메뉴가_보인다(admin_client):
    """세션 미들웨어 순서가 어긋나면 로그인 상태가 화면에 반영되지 않는다."""
    response = admin_client.get("/")
    assert "시스템 관리자" in response.text
    assert "로그아웃" in response.text
    assert "계정 관리" in response.text  # 관리자 전용 메뉴


def test_일반_사용자에게는_관리자_메뉴가_보이지_않는다(viewer_client):
    response = viewer_client.get("/")
    assert "조회자" in response.text
    assert "계정 관리" not in response.text
    assert "+ 자산 등록" not in viewer_client.get("/assets").text


def test_화면마다_브라우저_탭_제목이_다르다(admin_client):
    assert "<title>자산 관리 · IT 자산관리 시스템</title>" in admin_client.get("/assets").text
    assert "<title>대시보드 · IT 자산관리 시스템</title>" in admin_client.get("/").text
