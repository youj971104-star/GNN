"""알아보기 쉽고 쓰기 편하게 다듬은 화면들.

메뉴 아이콘·휴대폰 아래 탭, 어디서나 검색, 목록 위 상태 탭과 걸린 조건,
대시보드에서 눌러 들어가기, 직원 상세.
"""

import pathlib
import re
from datetime import date, timedelta

import pytest

from app.models import Asset, Employee
from app.services import assign_asset
from app.templating import CATEGORY_ICONS

SPRITE = pathlib.Path("app/static/icons/sprite.svg").read_text()


# --- 아이콘 ----------------------------------------------------------------------

def test_화면에서_쓰는_아이콘이_모두_그려져_있다():
    """sprite.svg 에 없는 이름을 부르면 빈칸이 된다."""
    templates = "\n".join(p.read_text() for p in pathlib.Path("app/templates").rglob("*.html"))
    used = set(re.findall(r"icon\('([a-z-]+)'", templates)) | set(CATEGORY_ICONS.values())
    missing = {name for name in used if f'id="i-{name}"' not in SPRITE}
    assert used and missing == set()


def test_아이콘_파일이_내려간다(client):
    response = client.get("/static/icons/sprite.svg")
    assert response.status_code == 200
    assert "image/svg+xml" in response.headers["content-type"]


def test_목록의_분류에_아이콘이_붙는다(admin_client, asset):
    html = admin_client.get("/assets").text
    assert '<span class="cat"><svg class="icon' in html
    assert "#i-laptop" in html             # 노트북


# --- 메뉴 ------------------------------------------------------------------------

def test_휴대폰용_아래_탭과_펼침_메뉴(admin_client):
    html = admin_client.get("/assets").text
    assert '<nav class="tabbar"' in html
    assert 'href="#sidebar" data-nav-open' in html          # 자바스크립트가 없어도 열린다
    assert 'id="sidebar"' in html
    # 지금 화면은 메뉴와 탭 양쪽에서 표시된다
    assert html.count('aria-current=page') == 2


def test_로그인_전에는_아래_탭이_없다(client):
    assert "tabbar" not in client.get("/login").text


def test_본문으로_건너뛰기(admin_client):
    html = admin_client.get("/").text
    assert 'class="skip-link" href="#main"' in html and 'id="main"' in html


def test_안내_문구에_닫기_단추(admin_client):
    """로그인 직후의 '환영합니다' 같은 문구를 닫을 수 있다."""
    assert "data-dismiss" in admin_client.get("/").text


# --- 어디서나 검색 ---------------------------------------------------------------

def test_위쪽_막대에_검색칸(admin_client):
    html = admin_client.get("/employees").text
    assert 'action="/search"' in html and "data-global-search" in html


@pytest.mark.parametrize("q", ["IT-2026-0001", "it-2026-0001", "https://ourcompany.duckdns.org/a/IT-2026-0001"])
def test_자산번호를_정확히_넣으면_그_자산으로(admin_client, asset, q):
    response = admin_client.get("/search", params={"q": q}, follow_redirects=False)
    assert response.status_code == 303
    assert response.headers["location"] == f"/assets/{asset.id}"


def test_사번을_정확히_넣으면_그_직원으로(admin_client, employee):
    response = admin_client.get("/search", params={"q": "e001"}, follow_redirects=False)
    assert response.headers["location"] == f"/employees/{employee.id}"


def test_일부만_넣으면_자산과_직원을_함께_보여_준다(admin_client, asset, employee):
    html = admin_client.get("/search", params={"q": "개발"}).text
    assert "자산 0건" in html                      # 아무에게도 지급되지 않아 자산은 안 찾힌다
    assert "직원 1명" in html and "홍길동" in html   # 부서 '개발팀' 으로 찾힘
    assert 'value="개발"' in html                  # 검색칸에 넣은 말이 남아 있다


def test_자산은_사용자_이름으로도_찾힌다(admin_client, db, asset, employee):
    assign_asset(db, asset=asset, employee=employee)
    html = admin_client.get("/search", params={"q": "홍길"}).text
    assert "테스트 노트북" in html and "홍길동" in html


def test_빈_검색은_자산_목록으로(admin_client):
    response = admin_client.get("/search", params={"q": "  "}, follow_redirects=False)
    assert response.headers["location"] == "/assets"


def test_검색은_로그인해야_한다(client):
    response = client.get("/search", params={"q": "x"}, follow_redirects=False)
    assert response.status_code in (302, 303)
    assert "/login" in response.headers["location"]


def test_검색어가_화면에_그대로_실행되지_않는다(admin_client):
    html = admin_client.get("/search", params={"q": '<script>alert(1)</script>'}).text
    assert "<script>alert(1)</script>" not in html


# --- 자산 목록: 상태 탭, 걸린 조건 ----------------------------------------------

@pytest.fixture
def mixed_assets(db):
    today = date.today()
    items = [
        Asset(asset_no="N-1", name="노트북1", category="NOTEBOOK", status="IN_STOCK"),
        Asset(asset_no="N-2", name="노트북2", category="NOTEBOOK", status="REPAIR",
              warranty_until=today + timedelta(days=10)),
        Asset(asset_no="M-1", name="모니터1", category="MONITOR", status="IN_STOCK",
              warranty_until=today - timedelta(days=10)),
        Asset(asset_no="M-2", name="모니터2", category="MONITOR", status="LOST",
              warranty_until=today + timedelta(days=5)),          # 분실은 보증을 챙기지 않는다
    ]
    db.add_all(items)
    db.commit()
    return items


def _tab_counts(html: str) -> dict[str, str]:
    tabs = re.search(r'<nav class="status-tabs".*?</nav>', html, re.S).group(0)
    return {
        label.strip(): count
        for label, count in re.findall(r'</span>([^<]+?)\s*<span class="count">([\d,]+)</span>', tabs)
    }


def test_상태_탭에_건수가_붙는다(admin_client, mixed_assets):
    counts = _tab_counts(admin_client.get("/assets").text)
    assert counts == {"재고": "2", "사용중": "0", "수리중": "1", "분실": "1", "폐기": "0"}


def test_상태_탭_건수는_다른_조건을_따른다(admin_client, mixed_assets):
    """분류를 노트북으로 걸면 탭의 숫자도 노트북만 센다."""
    counts = _tab_counts(admin_client.get("/assets?category=NOTEBOOK").text)
    assert counts["재고"] == "1" and counts["수리중"] == "1" and counts["분실"] == "0"


def test_상태_탭은_다른_조건을_지킨_채_상태만_바꾼다(admin_client, mixed_assets):
    html = admin_client.get("/assets?category=MONITOR&page=2").text
    assert 'href="/assets?category=MONITOR&amp;status=LOST"' in html
    assert 'href="/assets?category=MONITOR"' in html          # 전체 탭 (상태·쪽 번호를 뺀다)


def test_걸린_조건을_하나씩_풀_수_있다(admin_client, mixed_assets):
    html = admin_client.get("/assets?q=노트북&status=REPAIR").text
    assert "검색 결과 <strong>1</strong>건" in html
    assert "상태: 수리중" in html
    # 조건이 하나만 남아도 href 가 비지 않는다 (빈 href 는 '지금 주소 그대로' 라 안 풀린다)
    assert 'href="/assets?status=REPAIR" title="조건 풀기">검색어: 노트북' in html
    assert re.search(r'href="/assets\?q=[^"]+" title="조건 풀기">상태: 수리중', html)


def test_마지막_조건을_풀면_경로만_남는다(admin_client, mixed_assets):
    html = admin_client.get("/assets?status=REPAIR").text
    assert 'href="/assets" title="조건 풀기">상태: 수리중' in html


def test_고르기만_해도_검색된다(admin_client):
    assert 'class="filter-form" data-auto-submit' in admin_client.get("/assets").text


@pytest.mark.parametrize("warranty,expected", [("soon", {"N-2"}), ("expired", {"M-1"})])
def test_보증_조건(admin_client, mixed_assets, warranty, expected):
    html = admin_client.get(f"/assets?warranty={warranty}").text
    found = set(re.findall(r'data-href="/assets/\d+">\s*<td[^>]*><a [^>]*>([^<]+)</a>', html))
    assert found == expected


def test_이상한_보증_조건은_무시한다(admin_client, mixed_assets):
    html = admin_client.get("/assets?warranty=DROP").text
    assert "검색 결과" not in html


def test_사용자로_거른_목록은_이름을_보여_준다(admin_client, db, asset, employee):
    assign_asset(db, asset=asset, employee=employee)
    html = admin_client.get(f"/assets?holder_id={employee.id}").text
    assert "사용자: 홍길동" in html
    assert f'name="holder_id" value="{employee.id}"' in html    # 검색해도 유지


# --- 직원 목록 -------------------------------------------------------------------

def test_직원_재직상태_탭(admin_client, db):
    db.add_all([
        Employee(emp_no="A1", name="재직자", status="ACTIVE", department="개발팀"),
        Employee(emp_no="A2", name="휴직자", status="LEAVE", department="개발팀"),
        Employee(emp_no="A3", name="퇴사자", status="RESIGNED", department="영업팀"),
    ])
    db.commit()
    counts = _tab_counts(admin_client.get("/employees").text)
    assert counts == {"재직": "1", "휴직": "1", "퇴사": "1"}
    counts = _tab_counts(admin_client.get("/employees?department=개발팀").text)
    assert counts == {"재직": "1", "휴직": "1", "퇴사": "0"}


def test_퇴사했는데_자산을_가진_직원은_눈에_띈다(admin_client, db, asset, employee):
    assign_asset(db, asset=asset, employee=employee)
    employee.status = "RESIGNED"
    db.commit()
    html = admin_client.get("/employees").text
    assert 'class="row-warn"' in html and "회수 필요 1대" in html


def test_연락처는_눌러서_전화(admin_client, db):
    db.add(Employee(emp_no="T1", name="전화", phone="010-1234-5678", email="a@example.com"))
    db.commit()
    html = admin_client.get("/employees").text
    assert 'href="tel:01012345678"' in html and 'href="mailto:a@example.com"' in html


# --- 대시보드 --------------------------------------------------------------------

def test_숫자_타일을_누르면_그_목록으로(admin_client):
    html = admin_client.get("/").text
    for href in ("/assets", "/assets?status=IN_USE", "/assets?status=IN_STOCK",
                 "/assets?status=REPAIR", "/employees"):
        assert re.search(rf'<a class="stat[^"]*" href="{re.escape(href)}"', html), href


def test_확인할_일이_없으면_없다고_말한다(admin_client):
    assert "지금 따로 챙길 일이 없습니다" in admin_client.get("/").text


def test_확인할_일은_있는_것만_보여_준다(admin_client, mixed_assets):
    html = admin_client.get("/").text
    assert 'href="/assets?status=REPAIR" class="todo warn"' in html
    assert 'href="/assets?status=LOST" class="todo danger"' in html
    assert 'href="/assets?warranty=soon"' in html
    assert "퇴사자가 아직 갖고 있는 자산" not in html


def test_보증이_이미_끝난_자산은_건수로(admin_client, mixed_assets):
    html = admin_client.get("/").text
    assert "보증이 이미 끝난 자산 <strong>1건</strong>" in html
    assert 'href="/assets?warranty=expired"' in html


def test_분류와_부서_막대를_누르면_목록으로(admin_client, db, asset, employee):
    assign_asset(db, asset=asset, employee=employee)
    html = admin_client.get("/").text
    assert 'class="bar-row is-link" href="/assets?category=NOTEBOOK"' in html
    assert 'href="/assets?department=%EA%B0%9C%EB%B0%9C%ED%8C%80"' in html     # 개발팀


# --- 직원 상세 -------------------------------------------------------------------

def test_직원_상세에서_바로_지급(admin_client, employee):
    html = admin_client.get(f"/employees/{employee.id}").text
    assert f'href="/assignments/new?employee_id={employee.id}"' in html


def test_지급_화면에_그_직원이_골라져_있다(admin_client, asset, employee):
    html = admin_client.get(f"/assignments/new?employee_id={employee.id}").text
    assert re.search(rf'<option value="{employee.id}" selected', html)


def test_퇴사자가_자산을_가지면_경고(admin_client, db, asset, employee):
    assign_asset(db, asset=asset, employee=employee)
    employee.status = "RESIGNED"
    db.commit()
    html = admin_client.get(f"/employees/{employee.id}").text
    assert "퇴사한 직원이 자산 1대를 아직 갖고 있습니다" in html
    assert "/assignments/new?employee_id=" not in html          # 퇴사자에게는 지급 단추가 없다


def test_보유_자산이_없으면_지급하기_안내(admin_client, employee):
    assert "자산 지급하기" in admin_client.get(f"/employees/{employee.id}").text


def test_조회_계정에는_지급_단추가_없다(viewer_client, db):
    emp = Employee(emp_no="V1", name="조회대상")
    db.add(emp)
    db.commit()
    html = viewer_client.get(f"/employees/{emp.id}").text
    assert "/assignments/new" not in html
