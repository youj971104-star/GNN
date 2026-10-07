"""QR 스캔 화면과 조회 API."""

import pytest

from app import scanning
from app.models import Asset, Employee
from app.services import assign_asset


# --- 찍은 값에서 자산번호 꺼내기 ---------------------------------------------------

@pytest.mark.parametrize(
    "code,expected",
    [
        # 라벨 QR 에 들어 있는 주소
        ("https://gnsvce.duckdns.org/a/0121", "0121"),
        ("http://168.110.38.57:8000/a/0121", "0121"),
        ("https://gnsvce.duckdns.org/a/IT-2026-0007", "IT-2026-0007"),
        ("/a/0121", "0121"),
        ("https://gnsvce.duckdns.org/a/0121/", "0121"),
        # 장비에 원래 붙어 있던 바코드처럼 번호만 있는 경우
        ("0121", "0121"),
        ("IT-2026-0007", "IT-2026-0007"),
        # 알아볼 수 없는 값
        ("https://gnsvce.duckdns.org/assets/12", None),
        ("https://example.com/", None),
        ("사내 게시판 주소입니다", None),
        ("", None),
        (None, None),
        ("   ", None),
    ],
)
def test_찍은_값에서_자산번호를_꺼낸다(code, expected):
    assert scanning.parse_scanned_code(code) == expected


def test_너무_긴_값은_잘못_읽은_것으로_본다():
    assert scanning.parse_scanned_code("x" * 400) is None


@pytest.mark.parametrize(
    "code,expected",
    [
        ("https://gnsvce.duckdns.org/assets/12", 12),
        ("/assets/3/", 3),
        ("https://gnsvce.duckdns.org/a/0121", None),
        ("0121", None),
    ],
)
def test_자산_상세_주소를_찍으면_id_를_읽는다(code, expected):
    assert scanning.parse_asset_id(code) == expected


# --- 화면 -----------------------------------------------------------------------

def test_스캔_화면이_열린다(admin_client):
    page = admin_client.get("/scan").text
    assert "QR 스캔" in page
    assert "scanner.js" in page
    assert "jsQR.js" in page


def test_로그인해야_쓸_수_있다(client):
    response = client.get("/scan", follow_redirects=False)
    assert response.status_code == 303
    assert response.headers["location"].startswith("/login")


def test_조회_전용_계정도_스캔할_수_있다(viewer_client, db):
    """창고에서 확인만 하는 사람도 찍어볼 수 있어야 한다."""
    db.add(Asset(asset_no="0121", name="노트북"))
    db.commit()

    assert viewer_client.get("/scan").status_code == 200
    body = viewer_client.get("/scan/lookup", params={"code": "0121"}).json()
    assert body["ok"] is True
    assert body["can_manage"] is False


def test_해독기는_외부_주소가_아니라_우리_서버에서_받는다(admin_client):
    """사내망만 쓰는 회사에서도 동작해야 한다."""
    page = admin_client.get("/scan").text
    assert 'src="/static/js/vendor/jsQR.js"' in page
    assert admin_client.get("/static/js/vendor/jsQR.js").status_code == 200


# --- 조회 API --------------------------------------------------------------------

def test_라벨_주소를_찍으면_자산을_찾는다(admin_client, db):
    db.add(Asset(asset_no="0121", name="영업팀 노트북", category="NOTEBOOK",
                 status="IN_STOCK", model_name="LG 그램", location="본사 3층"))
    db.commit()

    body = admin_client.get(
        "/scan/lookup", params={"code": "https://gnsvce.duckdns.org/a/0121"}
    ).json()

    assert body["ok"] is True
    assert body["asset_no"] == "0121"
    assert body["name"] == "영업팀 노트북"
    assert body["category"] == "노트북"
    assert body["status"] == "재고"
    assert body["model"] == "LG 그램"
    assert body["location"] == "본사 3층"
    assert body["holder"] is None
    assert body["detail_url"].startswith("/assets/")


def test_지급된_자산은_사용자를_함께_보여준다(admin_client, db):
    asset = Asset(asset_no="0121", name="노트북", status="IN_STOCK")
    employee = Employee(emp_no="E0007", name="홍길동", department="영업팀")
    db.add_all([asset, employee])
    db.commit()
    assign_asset(db, asset=asset, employee=employee)
    db.commit()

    body = admin_client.get("/scan/lookup", params={"code": "0121"}).json()
    assert body["holder"]["name"] == "홍길동"
    assert body["holder"]["emp_no"] == "E0007"
    assert body["holder"]["department"] == "영업팀"
    assert body["holder"]["since"]
    assert body["action_label"] == "반납 처리"


def test_지급되지_않은_자산은_지급하기를_권한다(admin_client, db):
    db.add(Asset(asset_no="0121", name="노트북"))
    db.commit()

    body = admin_client.get("/scan/lookup", params={"code": "0121"}).json()
    assert body["action_label"] == "지급 처리"
    assert body["action_url"].endswith("#assign")


def test_자산_상세_주소를_찍어도_찾아진다(admin_client, db, asset):
    body = admin_client.get(
        "/scan/lookup", params={"code": f"https://gnsvce.duckdns.org/assets/{asset.id}"}
    ).json()
    assert body["ok"] is True
    assert body["id"] == asset.id


def test_없는_자산은_이유를_알려준다(admin_client):
    body = admin_client.get("/scan/lookup", params={"code": "0999"}).json()
    assert body["ok"] is False
    assert "0999" in body["error"]


def test_엉뚱한_QR_을_찍어도_안내만_한다(admin_client):
    """사내 게시판 QR 같은 것을 찍었을 때 오류로 죽으면 안 된다."""
    body = admin_client.get(
        "/scan/lookup", params={"code": "https://www.google.com/search?q=hello"}
    ).json()
    assert body["ok"] is False


def test_비로그인은_조회할_수_없다(client, db):
    db.add(Asset(asset_no="0121", name="노트북"))
    db.commit()

    response = client.get("/scan/lookup", params={"code": "0121"}, follow_redirects=False)
    assert response.status_code == 303
    assert response.headers["location"].startswith("/login")
