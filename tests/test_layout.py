"""화면 배치 - 넓은 모니터에서도 한눈에 보이게 모아 둔 구조가 유지되는지."""

import pathlib
import re

from app.models import Asset


def test_목록은_보통_폭_입력_화면은_좁은_폭(admin_client):
    assert 'class="page page-normal"' in admin_client.get("/assets").text
    assert 'class="page page-normal"' in admin_client.get("/").text
    for path in ("/assets/new", "/employees/new", "/assignments/new", "/settings", "/me/password"):
        assert 'class="page page-narrow"' in admin_client.get(path).text, path


def test_상단바도_본문과_같은_폭에_맞춘다(admin_client):
    html = admin_client.get("/assets/new").text
    assert 'class="topbar-inner page page-narrow"' in html


def test_목록_줄을_눌러_상세로_갈_수_있다(admin_client, asset, employee):
    assert f'data-href="/assets/{asset.id}"' in admin_client.get("/assets").text
    assert f'data-href="/employees/{employee.id}"' in admin_client.get("/employees").text


def test_자산_목록은_자산명과_모델을_한_칸에(admin_client, db):
    db.add(Asset(asset_no="0001", name="개발팀 노트북", model_name="그램 16", serial_no="SN-1"))
    db.commit()
    html = admin_client.get("/assets").text
    assert "자산명 · 모델" in html
    assert re.search(r'cell-title">개발팀 노트북<.*?cell-sub">\s*그램 16', html, re.S)


def test_자산_상세는_핵심값과_작업_패널로_나뉜다(admin_client, asset):
    html = admin_client.get(f"/assets/{asset.id}").text
    assert 'class="fact-strip"' in html
    assert 'class="detail-aside"' in html
    # QR 스캔 화면이 #assign 으로 바로 보낸다. 패널 안에 있어야 한다.
    aside = html.split('class="detail-aside"', 1)[1]
    assert 'id="assign"' in aside


def test_정비_추가_양식은_접어_둔다(admin_client, asset):
    html = admin_client.get(f"/assets/{asset.id}").text
    assert '<details class="add-panel">' in html
    assert 'action="/maintenance/new"' in html


def test_등록_화면의_저장_버튼은_따라온다(admin_client):
    assert 'class="form-actions sticky"' in admin_client.get("/assets/new").text


def test_QR_라벨_인쇄_스타일이_다른_화면을_건드리지_않는다():
    """예전에는 .label 이 대시보드 숫자 카드에까지 점선 테두리를 그렸다."""
    css = pathlib.Path("app/static/css/style.css").read_text()
    assert not re.search(r"^\s*\.label\s*\{", css, re.M)
    assert ".label-sheet .label {" in css


def test_금액_카드는_두_칸을_쓴다(admin_client):
    """총 취득가액은 자릿수가 많아 한 칸에 넣으면 잘린다."""
    html = admin_client.get("/").text
    assert re.search(r'class="stat wide"[^>]*>\s*<div class="label">총 취득가액', html)
