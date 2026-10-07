"""감가상각 계산 테스트."""

from datetime import date

import pytest

from app.models import Asset


def _asset(**overrides) -> Asset:
    values = {
        "asset_no": "IT-D-1",
        "name": "감가상각 대상",
        "purchase_price": 2_000_000,
        "purchase_date": date(2024, 1, 1),
        "useful_life_years": 4,
        "salvage_value": 0,
        "depreciation_method": "STRAIGHT_LINE",
    }
    values.update(overrides)
    return Asset(**values)


def test_정액법은_기간에_비례해_줄어든다():
    asset = _asset()
    assert asset.book_value(date(2024, 1, 1)) == 2_000_000   # 도입 시점
    assert asset.book_value(date(2025, 1, 1)) == 1_500_000   # 1년
    assert asset.book_value(date(2026, 1, 1)) == 1_000_000   # 2년
    assert asset.book_value(date(2028, 1, 1)) == 0           # 내용연수 종료


def test_내용연수가_지나도_0_밑으로_내려가지_않는다():
    assert _asset().book_value(date(2040, 1, 1)) == 0


def test_잔존가치_아래로는_내려가지_않는다():
    asset = _asset(salvage_value=200_000)
    assert asset.book_value(date(2040, 1, 1)) == 200_000
    assert asset.book_value(date(2026, 1, 1)) == 1_100_000  # (200만-20만)의 절반 상각


def test_월_단위로_계산한다():
    """연 단위로 계산하면 연중 도입 자산의 첫 해 상각이 과대 계상된다."""
    asset = _asset(purchase_date=date(2024, 7, 1))
    assert asset.book_value(date(2025, 1, 1)) == 1_750_000  # 6개월치만 상각


def test_정률법은_초기에_더_많이_상각된다():
    straight = _asset().book_value(date(2025, 1, 1))
    declining = _asset(depreciation_method="DECLINING").book_value(date(2025, 1, 1))
    assert declining < straight


def test_설정이_없으면_계산하지_않는다():
    assert _asset(depreciation_method="NONE").book_value() is None
    assert _asset(depreciation_method=None).book_value() is None
    assert _asset(purchase_price=None).book_value() is None
    assert _asset(purchase_date=None).book_value() is None
    assert _asset(useful_life_years=None).book_value() is None


def test_누계상각액과_진행률():
    asset = _asset()
    assert asset.accumulated_depreciation(date(2026, 1, 1)) == 1_000_000
    assert asset.depreciation_progress(date(2026, 1, 1)) == 50
    assert asset.depreciation_progress(date(2040, 1, 1)) == 100


def test_잔존가치가_취득가액보다_크면_취득가액으로_본다():
    asset = _asset(salvage_value=5_000_000)
    assert asset.book_value(date(2026, 1, 1)) == 2_000_000


def test_화면에서_감가상각을_설정한다(admin_client, db):
    response = admin_client.post(
        "/assets/new",
        data={
            "asset_no": "IT-DEP-1", "name": "노트북", "category": "NOTEBOOK",
            "status": "IN_STOCK", "purchase_date": "2024-01-01",
            "purchase_price": "2000000", "depreciation_method": "STRAIGHT_LINE",
            "useful_life_years": "4", "salvage_value": "0",
        },
        follow_redirects=False,
    )
    assert response.status_code == 303

    from sqlalchemy import select
    asset = db.scalar(select(Asset).where(Asset.asset_no == "IT-DEP-1"))
    assert asset.depreciation_method == "STRAIGHT_LINE"
    assert asset.useful_life_years == 4
    assert asset.depreciates


@pytest.mark.parametrize(
    "missing,message",
    [
        ({"useful_life_years": ""}, "내용연수"),
        ({"purchase_price": ""}, "취득가액"),
        ({"purchase_date": ""}, "도입일"),
    ],
)
def test_감가상각에_필요한_값이_없으면_거부한다(admin_client, missing, message):
    data = {
        "asset_no": "IT-DEP-2", "name": "노트북", "category": "NOTEBOOK",
        "status": "IN_STOCK", "purchase_date": "2024-01-01",
        "purchase_price": "2000000", "depreciation_method": "STRAIGHT_LINE",
        "useful_life_years": "4",
    }
    data.update(missing)
    response = admin_client.post("/assets/new", data=data)
    assert response.status_code == 400
    assert message in response.text


def test_잔존가치가_취득가액보다_크면_등록을_거부한다(admin_client):
    response = admin_client.post(
        "/assets/new",
        data={
            "asset_no": "IT-DEP-3", "name": "노트북", "category": "NOTEBOOK",
            "status": "IN_STOCK", "purchase_date": "2024-01-01",
            "purchase_price": "1000000", "depreciation_method": "STRAIGHT_LINE",
            "useful_life_years": "4", "salvage_value": "2000000",
        },
    )
    assert response.status_code == 400
    assert "잔존가치" in response.text
