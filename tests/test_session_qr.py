"""로그인 유지와 QR 스캔 흐름.

폰으로 QR 라벨을 찍을 때마다 로그인하지 않아도 되는지를 확인한다.
"""

import pyotp
import pytest

from app import config, deps, twofactor, useragent
from app.models import Asset, User
from app.security import hash_password

KAKAO_UA = (
    "Mozilla/5.0 (Linux; Android 14; SM-S911N) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Mobile Safari/537.36 KAKAOTALK 10.4.5"
)
IPHONE_KAKAO_UA = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Mobile/15E148 KAKAOTALK 10.4.0"
)
IPHONE_UA = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
)


# --- 로그인 유지 기간 ------------------------------------------------------------

def test_기본_로그인은_길게_유지된다(client):
    """폰으로 QR 을 찍을 때마다 로그인하지 않으려면 길게 유지돼야 한다."""
    client.post("/login", data={"username": "admin", "password": "admin1234"},
                follow_redirects=False)

    # 30일이 기본값이다
    assert config.SESSION_MAX_AGE >= 30 * 24 * 60 * 60
    assert client.get("/assets", follow_redirects=False).status_code == 200


def test_공용_PC_로_표시하면_짧게_유지된다(client, monkeypatch):
    client.post(
        "/login",
        data={"username": "admin", "password": "admin1234", "shared_device": "1"},
        follow_redirects=False,
    )
    assert client.get("/assets", follow_redirects=False).status_code == 200

    # 짧은 유지 시간이 지난 뒤에는 다시 로그인해야 한다
    later = deps.now_seconds() + config.SHORT_SESSION_MAX_AGE + 10
    monkeypatch.setattr(deps, "now_seconds", lambda: later)
    response = client.get("/assets", follow_redirects=False)
    assert response.status_code == 303
    assert response.headers["location"].startswith("/login")


def test_쓰는_동안에는_로그인이_풀리지_않는다(client, monkeypatch):
    """유지 시간은 마지막으로 쓴 시점부터 센다."""
    client.post("/login", data={"username": "admin", "password": "admin1234"},
                follow_redirects=False)

    # 기본 유지 시간의 절반쯤 지난 시점에 한 번 쓰면
    midway = deps.now_seconds() + config.SESSION_MAX_AGE - 100
    monkeypatch.setattr(deps, "now_seconds", lambda: midway)
    assert client.get("/assets", follow_redirects=False).status_code == 200

    # 그 시점부터 다시 세므로 아직 유효하다
    later = midway + config.SESSION_MAX_AGE - 100
    monkeypatch.setattr(deps, "now_seconds", lambda: later)
    assert client.get("/assets", follow_redirects=False).status_code == 200


def test_오래_안_쓰면_로그인이_풀린다(client, monkeypatch):
    client.post("/login", data={"username": "admin", "password": "admin1234"},
                follow_redirects=False)

    later = deps.now_seconds() + config.SESSION_MAX_AGE + 60
    monkeypatch.setattr(deps, "now_seconds", lambda: later)
    response = client.get("/assets", follow_redirects=False)
    assert response.status_code == 303
    assert response.headers["location"].startswith("/login")


def test_2단계_인증을_거쳐도_공용_PC_선택이_남는다(client, db, monkeypatch):
    secret = twofactor.new_secret()
    db.add(
        User(
            username="tfa", name="관리자", role="ADMIN",
            password_hash=hash_password("admin1234"),
            totp_secret=secret, totp_enabled=True,
        )
    )
    db.commit()

    client.post(
        "/login",
        data={"username": "tfa", "password": "admin1234", "shared_device": "1"},
        follow_redirects=False,
    )
    response = client.post(
        "/login/2fa",
        data={"code": pyotp.TOTP(secret).now(), "next": "/"},
        follow_redirects=False,
    )
    assert response.status_code == 303

    later = deps.now_seconds() + config.SHORT_SESSION_MAX_AGE + 10
    monkeypatch.setattr(deps, "now_seconds", lambda: later)
    assert client.get("/assets", follow_redirects=False).status_code == 303


# --- QR 스캔 후 로그인 흐름 -------------------------------------------------------

def test_QR_주소로_들어오면_로그인_후_그_자산으로_간다(client, db):
    db.add(Asset(asset_no="0121", name="스캔한 노트북"))
    db.commit()

    first = client.get("/a/0121", follow_redirects=False)
    assert first.status_code == 303
    assert first.headers["location"] == "/login?next=%2Fa%2F0121"

    client.post(
        "/login",
        data={"username": "admin", "password": "admin1234", "next": "/a/0121"},
        follow_redirects=False,
    )

    # 로그인 후 자산 상세까지 이어진다
    page = client.get("/a/0121", follow_redirects=True)
    assert page.status_code == 200
    assert "스캔한 노트북" in page.text


def test_로그인_후_검색_조건까지_돌아온다(client):
    """검색·필터를 걸어 둔 화면에서 로그인이 풀려도 같은 화면으로 돌아온다."""
    response = client.get("/assets?q=노트북&status=IN_STOCK", follow_redirects=False)
    assert response.status_code == 303

    # 로그인 화면이 돌아갈 주소를 그대로 품고 있고,
    login_page = client.get(response.headers["location"])
    assert 'name="next" value="/assets?q=%EB%85%B8%ED%8A%B8%EB%B6%81&amp;status=IN_STOCK"' in login_page.text

    # 로그인하면 그 주소로 보내 준다
    done = client.post(
        "/login",
        data={
            "username": "admin", "password": "admin1234",
            "next": "/assets?q=노트북&status=IN_STOCK",
        },
        follow_redirects=False,
    )
    assert done.headers["location"] == "/assets?q=%EB%85%B8%ED%8A%B8%EB%B6%81&status=IN_STOCK"

    # 그 화면에는 검색어가 그대로 들어가 있다
    listing = client.get(done.headers["location"])
    assert 'value="노트북"' in listing.text


def test_한_번_로그인하면_여러_자산을_이어서_찍을_수_있다(client, db):
    """QR 을 찍을 때마다 새 창이 열려도 로그인은 유지돼야 한다."""
    db.add_all([Asset(asset_no="0001", name="첫째"), Asset(asset_no="0002", name="둘째")])
    db.commit()

    client.post("/login", data={"username": "admin", "password": "admin1234"},
                follow_redirects=False)

    for asset_no, name in (("0001", "첫째"), ("0002", "둘째")):
        page = client.get(f"/a/{asset_no}", follow_redirects=True)
        assert page.status_code == 200
        assert name in page.text


# --- 앱 안의 브라우저 안내 --------------------------------------------------------

@pytest.mark.parametrize(
    "agent,expected",
    [
        (KAKAO_UA, "카카오톡"),
        (IPHONE_KAKAO_UA, "카카오톡"),
        ("Mozilla/5.0 ... NAVER(inapp; search; 1234; 12.0)", "네이버"),
        ("Mozilla/5.0 ... Instagram 300.0", "인스타그램"),
        (IPHONE_UA, None),
        ("Mozilla/5.0 (Windows NT 10.0) Chrome/126.0 Safari/537.36", None),
        ("Mozilla/5.0 (Macintosh) Whale/3.25 Safari/537.36", None),
        (None, None),
        ("", None),
    ],
)
def test_앱_안의_브라우저를_알아본다(agent, expected):
    assert useragent.in_app_browser(agent) == expected


def test_앱_안의_브라우저면_로그인_화면에서_안내한다(client):
    page = client.get("/login", headers={"user-agent": KAKAO_UA})
    assert "카카오톡 앱 안의 브라우저" in page.text
    assert "폰 기본 카메라" in page.text


def test_안드로이드면_크롬으로_여는_링크를_준다(client):
    page = client.get("/login?next=%2Fa%2F0121", headers={"user-agent": KAKAO_UA})
    assert "intent://" in page.text
    assert "/a/0121#Intent;scheme=http;package=com.android.chrome;end" in page.text


def test_아이폰_앱_브라우저에는_링크_대신_안내만_한다(client):
    """아이폰에는 다른 브라우저로 넘기는 방법이 없다."""
    page = client.get("/login?next=%2Fa%2F0121", headers={"user-agent": IPHONE_KAKAO_UA})
    assert "카카오톡 앱 안의 브라우저" in page.text
    assert "intent://" not in page.text


def test_보통_브라우저에는_안내를_띄우지_않는다(client):
    page = client.get("/login", headers={"user-agent": IPHONE_UA})
    assert "앱 안의 브라우저" not in page.text


def test_라벨_인쇄_화면에_찍는_방법을_안내한다(admin_client, db):
    db.add(Asset(asset_no="0001", name="노트북"))
    db.commit()
    page = admin_client.get("/assets/labels").text
    assert "폰 기본 카메라 앱으로 찍으세요" in page
