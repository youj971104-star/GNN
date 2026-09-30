"""정비 이력과 QR 라벨 테스트."""

from datetime import date, timedelta

from sqlalchemy import select

from app.labels import qr_svg, short_path
from app.models import Asset, Maintenance


def _form(**overrides) -> dict:
    data = {
        "maintained_at": date.today().isoformat(),
        "kind": "REPAIR",
        "vendor": "LG전자 서비스센터",
        "description": "키보드 교체",
        "cost": "85,000",
        "next_due": "",
    }
    data.update(overrides)
    return data


# --- 정비 이력 ----------------------------------------------------------------

def test_정비_이력을_등록한다(admin_client, db, asset):
    response = admin_client.post(
        "/maintenance/new", data=_form(asset_id=asset.id), follow_redirects=False
    )
    assert response.status_code == 303

    item = db.scalar(select(Maintenance).where(Maintenance.asset_id == asset.id))
    assert item.description == "키보드 교체"
    assert float(item.cost) == 85_000  # 쉼표가 있어도 숫자로 저장된다
    assert item.kind_label == "수리"


def test_작업_내용은_필수(admin_client, db, asset):
    admin_client.post(
        "/maintenance/new", data=_form(asset_id=asset.id, description="  "),
        follow_redirects=False,
    )
    assert db.scalar(select(Maintenance)) is None


def test_미래_날짜의_정비는_거부한다(admin_client, db, asset):
    future = (date.today() + timedelta(days=3)).isoformat()
    admin_client.post(
        "/maintenance/new", data=_form(asset_id=asset.id, maintained_at=future),
        follow_redirects=False,
    )
    assert db.scalar(select(Maintenance)) is None


def test_다음_점검일이_정비일보다_빠르면_거부한다(admin_client, db, asset):
    past = (date.today() - timedelta(days=5)).isoformat()
    admin_client.post(
        "/maintenance/new", data=_form(asset_id=asset.id, next_due=past),
        follow_redirects=False,
    )
    assert db.scalar(select(Maintenance)) is None


def test_정비_등록하며_수리중으로_바꿀_수_있다(admin_client, db, asset):
    admin_client.post(
        "/maintenance/new",
        data=_form(asset_id=asset.id, set_repairing="on"),
        follow_redirects=False,
    )
    db.expire_all()
    assert db.get(Asset, asset.id).status == "REPAIR"


def test_지급중인_자산은_상태를_바꾸지_않는다(admin_client, db, asset, employee):
    from app.services import assign_asset
    assign_asset(db, asset=asset, employee=employee)

    admin_client.post(
        "/maintenance/new",
        data=_form(asset_id=asset.id, set_repairing="on"),
        follow_redirects=False,
    )
    db.expire_all()
    assert db.get(Asset, asset.id).status == "IN_USE"  # 지급 상태가 유지된다


def test_누적_정비_비용을_합산한다(db, asset):
    db.add_all([
        Maintenance(asset_id=asset.id, description="수리1", cost=50_000),
        Maintenance(asset_id=asset.id, description="수리2", cost=30_000),
        Maintenance(asset_id=asset.id, description="점검", cost=None),
    ])
    db.commit()
    db.refresh(asset)
    assert asset.maintenance_total_cost == 80_000


def test_자산을_지우면_정비_이력도_함께_지워진다(admin_client, db, asset):
    admin_client.post("/maintenance/new", data=_form(asset_id=asset.id), follow_redirects=False)
    admin_client.post(f"/assets/{asset.id}/delete", follow_redirects=False)

    db.expunge_all()
    assert db.scalar(select(Maintenance)) is None


def test_일반_사용자는_정비를_등록할_수_없다(viewer_client, asset):
    response = viewer_client.post("/maintenance/new", data=_form(asset_id=asset.id))
    assert response.status_code == 403


def test_정비_이력_화면과_엑셀(admin_client, db, asset):
    admin_client.post("/maintenance/new", data=_form(asset_id=asset.id), follow_redirects=False)

    page = admin_client.get("/maintenance")
    assert page.status_code == 200
    assert "키보드 교체" in page.text

    export = admin_client.get("/maintenance/export")
    assert export.status_code == 200
    assert export.content[:2] == b"PK"


def test_다음_점검까지_남은_일수():
    item = Maintenance(description="점검", next_due=date.today() + timedelta(days=10))
    assert item.days_until_due() == 10
    assert Maintenance(description="점검").days_until_due() is None


# --- QR 라벨 ------------------------------------------------------------------

def test_QR_은_자산번호를_가리키는_짧은_주소를_담는다():
    assert short_path("IT-2026-0001") == "/a/IT-2026-0001"


def test_QR_은_HTML_에_바로_넣을_수_있는_SVG():
    svg = qr_svg("http://example.com/a/IT-1")
    assert svg.startswith("<svg")
    assert "<?xml" not in svg  # XML 선언이 있으면 HTML 안에서 깨진다
    assert "<path" in svg


def test_QR_주소로_들어오면_자산_상세로_보낸다(admin_client, asset):
    response = admin_client.get(f"/a/{asset.asset_no}", follow_redirects=False)
    assert response.status_code == 303
    assert response.headers["location"] == f"/assets/{asset.id}"


def test_없는_자산번호로_들어오면_목록으로_안내한다(admin_client):
    response = admin_client.get("/a/없는번호", follow_redirects=False)
    assert response.status_code == 303
    assert response.headers["location"] == "/assets"


def test_로그인하지_않으면_QR_주소도_로그인으로_보낸다(client, asset):
    response = client.get(f"/a/{asset.asset_no}", follow_redirects=False)
    assert response.status_code == 303
    assert response.headers["location"].startswith("/login")


def test_라벨_인쇄_화면은_검색_조건을_따른다(admin_client, db):
    db.add_all([
        Asset(asset_no="IT-N-1", name="노트북1", category="NOTEBOOK"),
        Asset(asset_no="IT-M-1", name="모니터1", category="MONITOR"),
    ])
    db.commit()

    response = admin_client.get("/assets/labels?category=NOTEBOOK")
    assert response.status_code == 200
    assert "IT-N-1" in response.text
    assert "IT-M-1" not in response.text
    assert "<svg" in response.text  # QR 이 실제로 들어 있다


def test_자산_상세에_QR_이_보인다(admin_client, asset):
    response = admin_client.get(f"/assets/{asset.id}")
    assert response.status_code == 200
    assert "<svg" in response.text
    assert f"/a/{asset.asset_no}" in response.text


def _viewbox_size(svg: str) -> float:
    """SVG 의 viewBox 한 변 길이. 단위는 라이브러리가 정하므로 비교용으로만 쓴다."""
    import re

    return float(re.search(r'viewBox="0 0 ([0-9.]+)', svg).group(1))


def test_QR_둘레_여백이_규격을_지킨다():
    """QR 규격은 둘레에 4칸의 빈 여백(quiet zone)을 요구한다.

    여백이 좁으면 스캐너가 QR 의 경계를 잡지 못해 인식률이 크게 떨어진다.
    실제로 여백을 1칸만 뒀을 때 라벨이 읽히지 않는 문제가 있었다.
    """
    import qrcode

    from app.labels import QUIET_ZONE, qr_svg

    assert QUIET_ZONE >= 4

    data = "http://example.com/a/IT-2026-0001"
    code = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, border=0)
    code.add_data(data)
    code.make(fit=True)
    modules = code.modules_count

    # 여백 없이 그린 것과 기본값으로 그린 것을 견줘 여백 칸 수를 역산한다.
    # (SVG 의 단위가 mm 라서 절대값으로는 칸 수를 알 수 없다)
    bare = _viewbox_size(qr_svg(data, box_size=1, border=0))
    padded = _viewbox_size(qr_svg(data, box_size=1))

    unit = bare / modules
    border_modules = round((padded - bare) / 2 / unit)
    assert border_modules >= 4, f"여백이 {border_modules}칸뿐입니다"


def test_QR_내용이_길어져도_생성된다():
    """주소가 길면 QR 버전이 올라가는데, 그래도 문제없이 만들어져야 한다."""
    from app.labels import qr_svg

    long_url = "http://very-long-company-hostname.example.co.kr:8000/a/IT-2026-000123456"
    svg = qr_svg(long_url)
    assert svg.startswith("<svg")
