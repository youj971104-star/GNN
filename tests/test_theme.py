"""다크 모드."""

import pathlib
import re

CSS = pathlib.Path("app/static/css/style.css").read_text()


def _block(selector: str) -> dict[str, str]:
    """선택자 바로 뒤 { … } 안의 색 변수들."""
    start = CSS.index(selector)
    body = CSS[CSS.index("{", start) + 1: CSS.index("}", start)]
    return dict(re.findall(r"(--[a-z0-9-]+):\s*([^;]+);", body))


LIGHT = _block(":root {")
DARK = _block(':root[data-theme="dark"]')
AUTO_DARK = _block(':root[data-theme="auto"]')
PRINT = _block('html:root[data-theme]')


# --- 화면 ------------------------------------------------------------------------

def test_처음에는_컴퓨터_설정을_따른다(admin_client):
    assert '<html lang="ko" data-theme="auto">' in admin_client.get("/assets").text


def test_고른_밝기가_쿠키로_남는다(admin_client):
    admin_client.cookies.set("theme", "dark")
    assert '<html lang="ko" data-theme="dark">' in admin_client.get("/assets").text
    admin_client.cookies.set("theme", "light")
    assert '<html lang="ko" data-theme="light">' in admin_client.get("/").text


def test_이상한_쿠키_값은_자동으로(admin_client):
    admin_client.cookies.set("theme", '"><script>alert(1)</script>')
    html = admin_client.get("/assets").text
    assert '<html lang="ko" data-theme="auto">' in html
    assert "<script>alert(1)" not in html


def test_로그인_화면도_따른다(client):
    client.cookies.set("theme", "dark")
    assert 'data-theme="dark"' in client.get("/login").text


def test_상단에_전환_단추가_있다(admin_client):
    html = admin_client.get("/assets").text
    assert "data-theme-toggle" in html
    assert "data-theme-label" in html
    assert 'name="color-scheme" content="light dark"' in html


# --- 색표 ------------------------------------------------------------------------

def test_어두운_색표_두_곳이_같다():
    """'항상 다크' 와 '자동인데 컴퓨터가 다크' 는 같은 색이어야 한다."""
    assert DARK == AUTO_DARK


def test_어두운_색표에_빠진_색이_없다():
    """밝은 색표에만 있는 변수가 있으면 다크 모드에서 그 부분만 밝게 남는다."""
    assert set(LIGHT) - {"--radius", "--sidebar-width"} == set(DARK)


def test_인쇄할_때는_밝은_색으로():
    assert {k: v for k, v in PRINT.items()} == {
        k: v for k, v in LIGHT.items() if k not in ("--radius", "--sidebar-width")
    }


def test_색은_변수로만_쓴다():
    """새 규칙에 색을 직접 박으면 다크 모드에서 그 부분만 튄다.

    사이드바(두 모드 모두 남색), 라벨 인쇄(종이), 카메라 화면(항상 검정)은 일부러 고정했다.
    """
    allowed = ("sidebar", "login-page", "login-card", "label", "scan-", "qr-", "print", "body {")
    rules = re.findall(r"([^{}]+)\{([^{}]*)\}", CSS)
    offenders = []
    for selector, body in rules:
        selector = selector.strip()
        if selector.startswith((":root", "html:root")) or "--" in body:
            continue
        if any(word in selector for word in allowed):
            continue
        if re.search(r"#[0-9a-fA-F]{3,6}\b|rgba?\(", body):
            offenders.append(selector)
    assert offenders == []


def test_QR_은_흰_바탕을_깐다():
    """어두운 바탕에 검은 칸이면 폰이 읽지 못한다."""
    rule = re.search(r"\.qr-compact svg, \.qr-box svg, \.label-qr svg \{([^}]*)\}", CSS).group(1)
    assert "background: #ffffff" in rule
