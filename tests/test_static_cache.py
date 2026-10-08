"""업데이트 뒤에 브라우저가 예전 스타일·스크립트를 계속 쓰지 않게 한다.

화면(HTML)은 새것인데 style.css 는 브라우저에 저장된 예전 것이 쓰이면,
아이콘이 화면 가득 크게 그려지는 등 화면이 깨진다 (실제로 겪은 일).
"""

import pathlib
import re

from app import templating
from app.templating import static_url

TEMPLATES = pathlib.Path("app/templates")


def test_정적_파일_주소에_내용_지문이_붙는다():
    url = static_url("css/style.css")
    assert re.fullmatch(r"/static/css/style\.css\?v=[0-9a-f]{12}", url)


def test_파일이_바뀌면_주소도_바뀐다(tmp_path, monkeypatch):
    (tmp_path / "a.css").write_text("body { color: red; }")
    monkeypatch.setattr(templating, "STATIC_DIR", tmp_path)
    before = static_url("a.css")
    (tmp_path / "a.css").write_text("body { color: blue; }")
    assert static_url("a.css") != before


def test_없는_파일은_지문_없이(monkeypatch, tmp_path):
    monkeypatch.setattr(templating, "STATIC_DIR", tmp_path)
    assert static_url("nope.js") == "/static/nope.js"


def test_화면이_스타일과_스크립트를_지문_붙은_주소로_부른다():
    """템플릿에 /static/css 나 /static/js 를 그대로 적으면 업데이트 뒤 예전 파일이 쓰인다."""
    offenders = []
    for path in TEMPLATES.rglob("*.html"):
        text = path.read_text()
        if re.search(r'(href|src)="/static/(css|js)/', text) or 'href="/static/icons/sprite.svg' in text:
            offenders.append(str(path))
    assert offenders == []


def test_실제_화면에도_지문이_붙어_있다(admin_client):
    html = admin_client.get("/assets").text
    assert re.search(r'href="/static/css/style\.css\?v=[0-9a-f]{12}"', html)
    assert re.search(r'src="/static/js/ui\.js\?v=[0-9a-f]{12}"', html)
    assert re.search(r'href="/static/icons/sprite\.svg\?v=[0-9a-f]{12}#i-', html)


def test_로그인_화면도(client):
    assert re.search(r'href="/static/css/style\.css\?v=', client.get("/login").text)


def test_지문_붙은_파일은_오래_저장(client):
    response = client.get(static_url("css/style.css"))
    assert response.status_code == 200
    assert response.headers["cache-control"] == "public, max-age=31536000, immutable"


def test_지문_없는_파일은_매번_확인(client):
    response = client.get("/static/css/style.css")
    assert response.headers["cache-control"] == "no-cache"
