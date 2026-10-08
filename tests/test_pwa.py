"""폰 홈 화면에 앱으로 설치하기 (PWA)."""

import json
import re
import pathlib
import struct

import pytest

STATIC = pathlib.Path("app/static")


def _png_size(path: pathlib.Path) -> tuple[int, int]:
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    return struct.unpack(">II", data[16:24])


# --- 앱 정보 파일 ----------------------------------------------------------------

def test_앱_정보_파일은_로그인_없이_받는다(client):
    response = client.get("/manifest.webmanifest")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/manifest+json")


def test_설치에_필요한_항목이_다_있다(client):
    """크롬·삼성 인터넷이 '설치할 수 있다'고 보는 조건."""
    manifest = client.get("/manifest.webmanifest").json()
    assert manifest["name"] and manifest["short_name"]
    assert manifest["start_url"] == "/" and manifest["scope"] == "/"
    assert manifest["display"] == "standalone"
    sizes = {icon["sizes"] for icon in manifest["icons"] if icon.get("purpose", "any") == "any"}
    assert {"192x192", "512x512"} <= sizes
    assert any(icon.get("purpose") == "maskable" for icon in manifest["icons"])


def test_아이콘_파일이_적힌_크기와_같다(client):
    manifest = client.get("/manifest.webmanifest").json()
    icons = manifest["icons"] + [i for s in manifest["shortcuts"] for i in s["icons"]]
    for icon in icons:
        response = client.get(icon["src"])
        assert response.status_code == 200, icon["src"]
        width, height = _png_size(STATIC / icon["src"].removeprefix("/static/"))
        assert f"{width}x{height}" == icon["sizes"], icon["src"]
    assert _png_size(STATIC / "icons/apple-touch-icon.png") == (180, 180)


def test_바로가기는_로그인한_화면으로_간다(admin_client):
    for shortcut in admin_client.get("/manifest.webmanifest").json()["shortcuts"]:
        assert admin_client.get(shortcut["url"]).status_code == 200


# --- 서비스 워커 -----------------------------------------------------------------

def test_서비스_워커는_사이트_맨_위에서_내려준다(client):
    """/static/ 아래에 두면 /static/ 화면만 맡을 수 있다."""
    response = client.get("/sw.js")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/javascript")
    assert response.headers["cache-control"] == "no-cache"     # 업데이트가 바로 퍼지게


def test_서비스_워커가_미리_받는_파일이_실제로_있다(client):
    source = client.get("/sw.js").text
    precache = json.loads(
        source.split("var PRECACHE = ", 1)[1].split(";", 1)[0].replace("OFFLINE_URL", '"/offline"')
    )
    for url in precache:
        assert client.get(url).status_code == 200, url


def test_서비스_워커는_개인정보_화면을_저장하지_않는다():
    """미리 받는 것은 안내 화면·스타일·아이콘뿐, 화면 이동은 언제나 서버에서."""
    source = (STATIC / "js/sw.js").read_text()
    assert source.count("cache.put") == 0
    assert 'request.method !== "GET"' in source


# --- 화면 ------------------------------------------------------------------------

def test_오프라인_화면은_로그인_없이_열린다(client):
    response = client.get("/offline")
    assert response.status_code == 200
    assert "인터넷에 연결되어 있지 않습니다" in response.text
    assert "<script" not in response.text


def test_오프라인_화면이_안내_문구를_가로채지_않는다(admin_client):
    """서비스 워커가 뒤에서 /offline 을 받아 가도, 다음 화면에 보여 줄 안내 문구는 남아야 한다."""
    # 로그인 직후라 '환영합니다' 가 다음 화면을 기다리고 있다
    assert admin_client.get("/offline").status_code == 200
    assert "환영합니다" in admin_client.get("/assets").text


def test_안내_문구가_여러_개_쌓여도_모두_보인다(admin_client):
    """앞선 문구('환영합니다')가 남아 있는 채로 새 문구가 붙어도 사라지지 않는다."""
    admin_client.get("/a/NO-SUCH-ASSET", follow_redirects=False)
    html = admin_client.get("/assets").text
    assert "환영합니다" in html and "NO-SUCH-ASSET" in html


@pytest.mark.parametrize("path", ["/", "/assets", "/scan"])
def test_모든_화면이_앱_정보를_알려_준다(admin_client, path):
    html = admin_client.get(path).text
    assert '<link rel="manifest" href="/manifest.webmanifest">' in html
    assert 'rel="apple-touch-icon"' in html
    assert re.search(r'<script src="/static/js/pwa\.js\?v=[0-9a-f]+" defer></script>', html)


def test_로그인_화면도_앱_정보를_알려_준다(client):
    html = client.get("/login").text
    assert 'rel="manifest"' in html and "pwa.js" in html


def test_설치_안내_화면(admin_client):
    html = admin_client.get("/install").text
    assert "갤럭시" in html and "아이폰" in html
    assert "data-install-app" in html
    assert 'href="/install" class="nav-install active"' in html


def test_설치_안내는_로그인해야_본다(client):
    response = client.get("/install", follow_redirects=False)
    assert response.status_code in (302, 303)
