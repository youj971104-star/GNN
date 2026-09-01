"""대시보드 통계와 직원/계정 화면 테스트."""

from datetime import date, timedelta

from app.models import Asset, Employee, User
from app.services import assign_asset, dashboard_stats, return_asset


def test_빈_상태에서도_대시보드가_열린다(admin_client):
    response = admin_client.get("/")
    assert response.status_code == 200


def test_상태별_집계(db, employee):
    db.add_all(
        [
            Asset(asset_no="A1", name="재고1", status="IN_STOCK"),
            Asset(asset_no="A2", name="재고2", status="IN_STOCK"),
            Asset(asset_no="A3", name="수리중", status="REPAIR"),
            Asset(asset_no="A4", name="폐기", status="DISPOSED"),
        ]
    )
    db.commit()
    in_use = db.query(Asset).filter(Asset.asset_no == "A1").one()
    assign_asset(db, asset=in_use, employee=employee)

    stats = dashboard_stats(db)
    assert stats["total"] == 4
    assert stats["status_counts"]["IN_STOCK"] == 1
    assert stats["status_counts"]["IN_USE"] == 1
    assert stats["status_counts"]["REPAIR"] == 1
    assert stats["status_counts"]["DISPOSED"] == 1


def test_총_취득가액과_분류별_집계(db):
    db.add_all(
        [
            Asset(asset_no="A1", name="노트북1", category="NOTEBOOK", purchase_price=2_000_000),
            Asset(asset_no="A2", name="노트북2", category="NOTEBOOK", purchase_price=1_500_000),
            Asset(asset_no="A3", name="모니터1", category="MONITOR", purchase_price=500_000),
            Asset(asset_no="A4", name="가격없음", category="MONITOR"),
        ]
    )
    db.commit()

    stats = dashboard_stats(db)
    assert stats["total_amount"] == 4_000_000

    by_category = {row["code"]: row for row in stats["by_category"]}
    assert by_category["NOTEBOOK"]["count"] == 2
    assert by_category["NOTEBOOK"]["amount"] == 3_500_000
    assert by_category["MONITOR"]["count"] == 2


def test_부서별_보유_현황은_지급된_자산만_센다(db, asset, employee):
    stats = dashboard_stats(db)
    assert stats["by_department"] == []

    assign_asset(db, asset=asset, employee=employee)
    stats = dashboard_stats(db)
    assert stats["by_department"] == [{"label": "개발팀", "count": 1}]


def test_보증_만료_임박_자산을_찾아낸다(db):
    today = date.today()
    db.add_all(
        [
            Asset(asset_no="A1", name="곧 만료", warranty_until=today + timedelta(days=30)),
            Asset(asset_no="A2", name="여유 있음", warranty_until=today + timedelta(days=400)),
            Asset(asset_no="A3", name="이미 만료", warranty_until=today - timedelta(days=5)),
            Asset(asset_no="A4", name="폐기됨", status="DISPOSED", warranty_until=today),
        ]
    )
    db.commit()

    names = {asset.name for asset in dashboard_stats(db)["warranty_soon"]}
    assert names == {"곧 만료", "이미 만료"}  # 폐기 자산은 제외된다


def test_퇴사자가_보유_중인_자산을_알려준다(db, asset, employee):
    assign_asset(db, asset=asset, employee=employee)
    employee.status = "RESIGNED"  # 실제 화면에선 막히지만, 이전 데이터가 있을 수 있다
    db.commit()

    holding = dashboard_stats(db)["resigned_holding"]
    assert len(holding) == 1
    assert holding[0].employee.name == employee.name


def test_최근_이력은_반납_건도_함께_보여준다(db, asset, employee):
    assignment = assign_asset(db, asset=asset, employee=employee)
    return_asset(db, assignment=assignment)

    recent = dashboard_stats(db)["recent_assignments"]
    assert len(recent) == 1
    assert not recent[0].is_open


def test_직원_등록과_사번_중복_검사(admin_client, db):
    response = admin_client.post(
        "/employees/new",
        data={"emp_no": "E100", "name": "신입사원", "department": "개발팀", "status": "ACTIVE"},
        follow_redirects=False,
    )
    assert response.status_code == 303
    assert db.query(Employee).filter(Employee.emp_no == "E100").count() == 1

    duplicate = admin_client.post(
        "/employees/new", data={"emp_no": "E100", "name": "다른사람", "status": "ACTIVE"}
    )
    assert duplicate.status_code == 400
    assert "이미 등록" in duplicate.text


def test_이메일_형식을_검사한다(admin_client):
    response = admin_client.post(
        "/employees/new",
        data={"emp_no": "E101", "name": "홍길동", "email": "잘못된주소", "status": "ACTIVE"},
    )
    assert response.status_code == 400
    assert "이메일" in response.text


def test_지급_이력이_있는_직원은_삭제되지_않는다(admin_client, db, asset, employee):
    assign_asset(db, asset=asset, employee=employee)
    admin_client.post(f"/employees/{employee.id}/delete", follow_redirects=False)

    db.expunge_all()
    assert db.query(Employee).filter(Employee.emp_no == employee.emp_no).count() == 1


def test_계정_생성과_권한_지정(admin_client, db):
    response = admin_client.post(
        "/users/new",
        data={
            "username": "helpdesk",
            "name": "헬프데스크",
            "role": "USER",
            "password": "helpdesk1234",
            "confirm_password": "helpdesk1234",
        },
        follow_redirects=False,
    )
    assert response.status_code == 303

    account = db.query(User).filter(User.username == "helpdesk").one()
    assert account.role == "USER" and account.is_active


def test_비밀번호_확인이_다르면_계정이_생성되지_않는다(admin_client, db):
    response = admin_client.post(
        "/users/new",
        data={
            "username": "helpdesk",
            "name": "헬프데스크",
            "role": "USER",
            "password": "helpdesk1234",
            "confirm_password": "different1234",
        },
    )
    assert response.status_code == 400
    assert db.query(User).filter(User.username == "helpdesk").count() == 0


def test_마지막_관리자의_권한은_내릴_수_없다(admin_client, db):
    admin = db.query(User).filter(User.username == "admin").one()
    response = admin_client.post(
        f"/users/{admin.id}/edit",
        data={"name": "시스템 관리자", "role": "USER", "is_active": "on"},
    )
    assert response.status_code == 400
    assert "관리자" in response.text

    db.expire_all()
    assert db.query(User).filter(User.username == "admin").one().role == "ADMIN"


def test_본인_계정은_삭제할_수_없다(admin_client, db):
    admin = db.query(User).filter(User.username == "admin").one()
    admin_client.post(f"/users/{admin.id}/delete", follow_redirects=False)

    db.expunge_all()
    assert db.query(User).filter(User.username == "admin").count() == 1
