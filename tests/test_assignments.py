"""지급 / 반납 업무 규칙 테스트."""

from datetime import date, timedelta

import pytest
from sqlalchemy import select

from app.models import Asset, Assignment, Employee
from app.services import BusinessError, assign_asset, open_assignment, return_asset


def test_지급하면_자산이_사용중이_되고_이력이_남는다(db, asset, employee):
    assignment = assign_asset(db, asset=asset, employee=employee, actor="admin")

    assert asset.status == "IN_USE"
    assert asset.holder_id == employee.id
    assert assignment.is_open
    assert assignment.created_by == "admin"


def test_이미_지급된_자산은_다시_지급할_수_없다(db, asset, employee):
    assign_asset(db, asset=asset, employee=employee)
    other = Employee(emp_no="E002", name="김철수")
    db.add(other)
    db.commit()

    with pytest.raises(BusinessError, match="이미 지급"):
        assign_asset(db, asset=asset, employee=other)


def test_폐기된_자산은_지급할_수_없다(db, employee):
    disposed = Asset(asset_no="IT-X", name="폐기 자산", status="DISPOSED")
    db.add(disposed)
    db.commit()

    with pytest.raises(BusinessError, match="지급할 수 없습니다"):
        assign_asset(db, asset=disposed, employee=employee)


def test_퇴사자에게는_지급할_수_없다(db, asset):
    resigned = Employee(emp_no="E900", name="퇴사자", status="RESIGNED")
    db.add(resigned)
    db.commit()

    with pytest.raises(BusinessError, match="퇴사"):
        assign_asset(db, asset=asset, employee=resigned)


def test_미래_날짜로는_지급할_수_없다(db, asset, employee):
    with pytest.raises(BusinessError, match="오늘 이후"):
        assign_asset(db, asset=asset, employee=employee, assigned_at=date.today() + timedelta(days=1))


def test_반납하면_재고로_돌아가고_보유자가_비워진다(db, asset, employee):
    assignment = assign_asset(db, asset=asset, employee=employee)
    return_asset(db, assignment=assignment, new_status="IN_STOCK", actor="admin")

    assert asset.status == "IN_STOCK"
    assert asset.holder_id is None
    assert not assignment.is_open
    assert assignment.returned_at == date.today()


def test_반납하면서_수리중_상태로_보낼_수_있다(db, asset, employee):
    assignment = assign_asset(db, asset=asset, employee=employee)
    return_asset(db, assignment=assignment, new_status="REPAIR", note="키보드 불량")

    assert asset.status == "REPAIR"
    assert assignment.return_note == "키보드 불량"


def test_반납일은_지급일보다_빠를_수_없다(db, asset, employee):
    assignment = assign_asset(db, asset=asset, employee=employee, assigned_at=date.today())
    with pytest.raises(BusinessError, match="반납일"):
        return_asset(db, assignment=assignment, returned_at=date.today() - timedelta(days=3))


def test_이미_반납한_건은_다시_반납할_수_없다(db, asset, employee):
    assignment = assign_asset(db, asset=asset, employee=employee)
    return_asset(db, assignment=assignment)

    with pytest.raises(BusinessError, match="이미 반납"):
        return_asset(db, assignment=assignment)


def test_반납_후_같은_직원에게_다시_지급하면_이력이_두_건이_된다(db, asset, employee):
    first = assign_asset(db, asset=asset, employee=employee, assigned_at=date.today() - timedelta(days=30))
    return_asset(db, assignment=first, returned_at=date.today() - timedelta(days=10))
    assign_asset(db, asset=asset, employee=employee)

    history = db.scalars(select(Assignment).where(Assignment.asset_id == asset.id)).all()
    assert len(history) == 2
    assert open_assignment(db, asset.id) is not None


def test_보유_자산이_있으면_퇴사_처리를_막는다(admin_client, db, asset, employee):
    assign_asset(db, asset=asset, employee=employee)
    response = admin_client.post(
        f"/employees/{employee.id}/edit",
        data={"name": employee.name, "department": "개발팀", "status": "RESIGNED"},
    )
    assert response.status_code == 400
    assert "반납" in response.text


def test_화면에서_지급하고_반납한다(admin_client, db, asset, employee):
    admin_client.post(
        "/assignments/new",
        data={
            "asset_id": asset.id,
            "employee_id": employee.id,
            "assigned_at": date.today().isoformat(),
            "assigned_note": "신규 입사자 지급",
        },
        follow_redirects=False,
    )
    db.expire_all()
    assert db.get(Asset, asset.id).status == "IN_USE"

    assignment = open_assignment(db, asset.id)
    admin_client.post(
        f"/assignments/{assignment.id}/return",
        data={"returned_at": date.today().isoformat(), "new_status": "IN_STOCK"},
        follow_redirects=False,
    )
    db.expire_all()
    assert db.get(Asset, asset.id).status == "IN_STOCK"
    assert db.get(Asset, asset.id).holder_id is None


def test_일반_사용자는_지급_처리를_할_수_없다(viewer_client, asset, employee):
    response = viewer_client.post(
        "/assignments/new", data={"asset_id": asset.id, "employee_id": employee.id}
    )
    assert response.status_code == 403


def test_이력_화면에서_미반납_건만_걸러본다(admin_client, db, asset, employee):
    other = Asset(asset_no="IT-B", name="반납된 자산")
    db.add(other)
    db.commit()
    assign_asset(db, asset=asset, employee=employee)
    closed = assign_asset(db, asset=other, employee=employee)
    return_asset(db, assignment=closed)

    response = admin_client.get("/assignments?state=open")
    assert asset.name in response.text
    assert "반납된 자산" not in response.text
