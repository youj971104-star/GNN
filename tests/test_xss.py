"""자산번호·이름에 심어 둔 코드가 실행되지 않는지 확인한다.

예전에는 onsubmit="return confirm('... {{ 자산번호 }} ...')" 처럼 썼다.
자산번호에 따옴표가 들어 있으면 자바스크립트 문자열이 거기서 끊겨,
그 뒤에 적어 둔 코드가 관리자 브라우저에서 실행됐다.
"""

import pathlib
import re

import pytest

from app.models import Asset, Employee, User
from app.security import hash_password

# 따옴표로 문자열을 끊고 코드를 이어 붙이는 전형적인 형태
PAYLOAD = "0121'+alert('터짐')+'"


def _js_handlers(html: str) -> list[str]:
    """화면에 남아 있는 인라인 자바스크립트 속성들."""
    return re.findall(r'on(?:submit|click|change|error|load)="[^"]*"', html)


def test_자산번호에_따옴표를_넣어도_코드가_되지_않는다(admin_client, db):
    db.add(Asset(asset_no=PAYLOAD, name="공격 테스트"))
    db.commit()
    asset = db.query(Asset).filter_by(asset_no=PAYLOAD).one()

    html = admin_client.get(f"/assets/{asset.id}").text

    # 확인 문구는 속성 값으로만 들어가고, 자바스크립트 문자열로 만들어지지 않는다
    assert "data-confirm=" in html
    assert not any("confirm(" in handler for handler in _js_handlers(html))
    assert "alert(" not in "".join(_js_handlers(html))


def test_직원_이름도_마찬가지다(admin_client, db):
    db.add(Employee(emp_no="E9999", name=PAYLOAD))
    db.commit()
    employee = db.query(Employee).filter_by(emp_no="E9999").one()

    html = admin_client.get(f"/employees/{employee.id}").text
    assert not any("confirm(" in handler for handler in _js_handlers(html))


def test_계정_아이디도_마찬가지다(admin_client, db):
    db.add(User(username="ev'il", name=PAYLOAD, role="USER",
                password_hash=hash_password("viewer1234")))
    db.commit()

    html = admin_client.get("/users").text
    assert not any("confirm(" in handler for handler in _js_handlers(html))


@pytest.mark.parametrize(
    "path", sorted(str(p) for p in pathlib.Path("app/templates").rglob("*.html"))
)
def test_화면_어디에도_인라인_confirm_이_남아_있지_않다(path):
    """값이 자바스크립트 문자열로 들어가는 길을 아예 막아 둔다."""
    text = pathlib.Path(path).read_text()
    for handler in _js_handlers(text):
        assert "confirm(" not in handler, f"{path}: {handler[:60]}"


def test_확인_창_스크립트가_모든_화면에_붙어_있다(admin_client):
    assert '/static/js/confirm.js' in admin_client.get("/assets").text
    assert admin_client.get("/static/js/confirm.js").status_code == 200


# --- 보안 헤더 ------------------------------------------------------------------

def test_모든_응답에_보안_헤더가_붙는다(admin_client):
    response = admin_client.get("/assets")
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert response.headers["Referrer-Policy"] == "same-origin"

    csp = response.headers["Content-Security-Policy"]
    assert "script-src 'self'" in csp          # 화면 안 자바스크립트는 실행되지 않는다
    assert "frame-ancestors 'none'" in csp     # 다른 사이트에 끼워 넣을 수 없다
    assert "object-src 'none'" in csp


def test_로그인_화면에도_붙는다(client):
    assert client.get("/login").headers["X-Frame-Options"] == "DENY"


def test_HTTPS_로_쓸_때만_HSTS_를_보낸다(client, monkeypatch):
    from app import config, main

    assert "Strict-Transport-Security" not in client.get("/login").headers

    monkeypatch.setattr(config, "HTTPS_ONLY", True)
    monkeypatch.setattr(main.config, "HTTPS_ONLY", True)
    assert "Strict-Transport-Security" in client.get("/login").headers
