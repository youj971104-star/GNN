"""자산 검색에 직원 조건 추가 / 드롭다운 검색 테스트."""

from sqlalchemy import select

from app.models import Asset, Employee
from app.services import AssetFilter, search_assets


def _setup(db):
    """서로 다른 부서의 직원 둘에게 자산을 하나씩 지급한 상태를 만든다."""
    from app.services import assign_asset

    kim = Employee(emp_no="E100", name="김서준", department="개발팀")
    lee = Employee(emp_no="E200", name="이하윤", department="디자인팀")
    db.add_all([kim, lee])

    laptop = Asset(asset_no="IT-A", name="노트북", category="NOTEBOOK")
    monitor = Asset(asset_no="IT-B", name="모니터", category="MONITOR")
    spare = Asset(asset_no="IT-C", name="예비 장비", category="ETC")
    db.add_all([laptop, monitor, spare])
    db.commit()

    assign_asset(db, asset=laptop, employee=kim)
    assign_asset(db, asset=monitor, employee=lee)
    return {"kim": kim, "lee": lee, "laptop": laptop, "monitor": monitor, "spare": spare}


def _found(db, keyword):
    result = search_assets(db, AssetFilter(q=keyword))
    return {asset.asset_no for asset in result.items}


def test_직원_이름으로_자산을_찾는다(db):
    _setup(db)
    assert _found(db, "김서준") == {"IT-A"}
    assert _found(db, "이하윤") == {"IT-B"}


def test_사번으로도_찾는다(db):
    _setup(db)
    assert _found(db, "E100") == {"IT-A"}


def test_부서로도_찾는다(db):
    _setup(db)
    assert _found(db, "개발팀") == {"IT-A"}
    assert _found(db, "디자인팀") == {"IT-B"}


def test_지급되지_않은_자산은_직원_검색에_걸리지_않는다(db):
    _setup(db)
    assert "IT-C" not in _found(db, "김서준")


def test_반납하면_직원_검색에서_빠진다(db):
    data = _setup(db)
    from app.services import open_assignment, return_asset

    return_asset(db, assignment=open_assignment(db, data["laptop"].id))
    assert _found(db, "김서준") == set()


def test_기존_자산_검색은_그대로_동작한다(db):
    _setup(db)
    assert _found(db, "노트북") == {"IT-A"}
    assert _found(db, "IT-B") == {"IT-B"}
    assert _found(db, "예비") == {"IT-C"}


def test_이름과_자산명이_함께_걸리면_둘_다_나온다(db):
    """직원 이름이 자산명에도 들어 있는 경우 (OR 조건이라 합쳐져야 한다)."""
    _setup(db)
    db.add(Asset(asset_no="IT-D", name="김서준 전용 도킹스테이션"))
    db.commit()

    assert _found(db, "김서준") == {"IT-A", "IT-D"}


def test_화면_검색창_안내문에_사용자가_포함된다(admin_client, db):
    _setup(db)
    page = admin_client.get("/assets")
    assert "사용자 이름" in page.text

    result = admin_client.get("/assets?q=김서준")
    assert "IT-A" in result.text
    assert "IT-C" not in result.text


# --- 드롭다운 검색 ------------------------------------------------------------

def test_지급_화면_드롭다운에_검색_정보가_실린다(admin_client, db):
    _setup(db)
    page = admin_client.get("/assignments/new")

    assert 'data-searchable=' in page.text          # 검색칸이 붙는다
    assert 'data-search="김서준 E100 개발팀' in page.text   # 이름·사번·부서로 찾을 수 있다


def test_자산_상세_지급폼에도_검색이_붙는다(admin_client, db):
    data = _setup(db)
    page = admin_client.get(f"/assets/{data['spare'].id}")
    assert 'data-searchable=' in page.text


def test_검색_스크립트가_서빙된다(admin_client):
    response = admin_client.get("/static/js/searchable-select.js")
    assert response.status_code == 200
    assert "searchable" in response.text
