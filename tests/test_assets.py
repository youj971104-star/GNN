"""자산 등록/조회/수정/삭제와 검색 테스트."""

from datetime import date, timedelta

from sqlalchemy import select

from app.models import Asset


def _asset_form(**overrides) -> dict:
    data = {
        "asset_no": "IT-2026-9001",
        "name": "개발팀 노트북",
        "category": "NOTEBOOK",
        "status": "IN_STOCK",
        "manufacturer": "LG전자",
        "model_name": "그램 16",
        "serial_no": "SN-TEST-001",
        "spec": "i7 / 32GB",
        "location": "본사 3층",
        "supplier": "테크상사",
        "purchase_date": "2026-01-15",
        "purchase_price": "2,150,000",
        "warranty_until": "2029-01-14",
        "license_key": "",
        "note": "",
    }
    data.update(overrides)
    return data


def test_자산_등록(admin_client, db):
    response = admin_client.post("/assets/new", data=_asset_form(), follow_redirects=False)
    assert response.status_code == 303

    asset = db.scalar(select(Asset).where(Asset.asset_no == "IT-2026-9001"))
    assert asset is not None
    assert asset.name == "개발팀 노트북"
    assert float(asset.purchase_price) == 2_150_000  # 쉼표가 있어도 숫자로 저장된다
    assert asset.purchase_date == date(2026, 1, 15)


def test_자산번호는_중복될_수_없다(admin_client, asset):
    response = admin_client.post(
        "/assets/new", data=_asset_form(asset_no=asset.asset_no)
    )
    assert response.status_code == 400
    assert "이미 등록되어" in response.text


def test_자산명이_없으면_등록되지_않는다(admin_client):
    response = admin_client.post("/assets/new", data=_asset_form(name="   "))
    assert response.status_code == 400
    assert "필수 입력" in response.text


def test_보증만료일이_도입일보다_빠르면_거부한다(admin_client):
    response = admin_client.post(
        "/assets/new", data=_asset_form(purchase_date="2026-05-01", warranty_until="2026-04-01")
    )
    assert response.status_code == 400
    assert "보증만료일" in response.text


def test_미래의_도입일은_거부한다(admin_client):
    future = (date.today() + timedelta(days=10)).isoformat()
    response = admin_client.post("/assets/new", data=_asset_form(purchase_date=future))
    assert response.status_code == 400
    assert "오늘 이후" in response.text


def test_취득가액에_문자가_들어가면_거부한다(admin_client):
    response = admin_client.post("/assets/new", data=_asset_form(purchase_price="이백만원"))
    assert response.status_code == 400
    assert "숫자" in response.text


def test_자산_수정(admin_client, db, asset):
    response = admin_client.post(
        f"/assets/{asset.id}/edit",
        data=_asset_form(name="수정된 자산명", location="본사 5층"),
        follow_redirects=False,
    )
    assert response.status_code == 303

    db.expire_all()
    updated = db.get(Asset, asset.id)
    assert updated.name == "수정된 자산명"
    assert updated.location == "본사 5층"


def test_자산_삭제(admin_client, db, asset):
    asset_no = asset.asset_no
    response = admin_client.post(f"/assets/{asset.id}/delete", follow_redirects=False)
    assert response.status_code == 303

    db.expunge_all()
    assert db.scalar(select(Asset).where(Asset.asset_no == asset_no)) is None


def test_없는_자산을_열면_404(admin_client):
    assert admin_client.get("/assets/99999").status_code == 404


def test_검색어로_자산을_찾는다(admin_client, db):
    db.add_all(
        [
            Asset(asset_no="IT-A", name="개발팀 노트북", category="NOTEBOOK", serial_no="SN-AAA"),
            Asset(asset_no="IT-B", name="회의실 모니터", category="MONITOR", serial_no="SN-BBB"),
        ]
    )
    db.commit()

    hit = admin_client.get("/assets?q=모니터")
    assert "회의실 모니터" in hit.text
    assert "개발팀 노트북" not in hit.text

    by_serial = admin_client.get("/assets?q=SN-AAA")
    assert "개발팀 노트북" in by_serial.text


def test_분류와_상태로_필터링한다(admin_client, db):
    db.add_all(
        [
            Asset(asset_no="IT-A", name="노트북1", category="NOTEBOOK", status="IN_STOCK"),
            Asset(asset_no="IT-B", name="모니터1", category="MONITOR", status="REPAIR"),
        ]
    )
    db.commit()

    result = admin_client.get("/assets?category=MONITOR")
    assert "모니터1" in result.text and "노트북1" not in result.text

    result = admin_client.get("/assets?status=REPAIR")
    assert "모니터1" in result.text and "노트북1" not in result.text


def test_지급중인_자산은_삭제할_수_없다(admin_client, db, asset, employee):
    admin_client.post(
        "/assignments/new",
        data={"asset_id": asset.id, "employee_id": employee.id, "assigned_at": date.today().isoformat()},
        follow_redirects=False,
    )
    admin_client.post(f"/assets/{asset.id}/delete", follow_redirects=False)

    db.expunge_all()
    assert db.scalar(select(Asset).where(Asset.asset_no == asset.asset_no)) is not None


def test_지급중인_자산의_상태는_폼에서_바꿀_수_없다(admin_client, asset, employee):
    admin_client.post(
        "/assignments/new",
        data={"asset_id": asset.id, "employee_id": employee.id, "assigned_at": date.today().isoformat()},
    )
    response = admin_client.post(
        f"/assets/{asset.id}/edit", data=_asset_form(asset_no=asset.asset_no, status="DISPOSED")
    )
    assert response.status_code == 400
    assert "반납" in response.text
