"""자산번호·사번 자동 채번 테스트."""

import pytest
from sqlalchemy import select

from app import numbering
from app.models import Asset, Employee
from app.settings_store import get_text, set_value


# --- 기존 번호에서 규칙 읽기 ------------------------------------------------------

@pytest.mark.parametrize(
    "value,expected",
    [
        ("0121", ("", "0121")),
        ("E0103", ("E", "0103")),
        ("IT-2026-0015", ("IT-2026-", "0015")),
        ("A-1", ("A-", "1")),
        ("번호없음", None),
        ("", None),
    ],
)
def test_번호를_접두사와_숫자로_나눈다(value, expected):
    assert numbering.split_number(value) == expected


@pytest.mark.parametrize(
    "existing,prefix,padding,expected",
    [
        ([f"{i:04d}" for i in range(1, 122)], "", 4, "0122"),      # 이관한 자산
        ([f"E{i:04d}" for i in range(1, 104)], "E", 4, "E0104"),   # 이관한 직원
        (["IT-2026-0001", "IT-2026-0015"], "IT-2026-", 4, "IT-2026-0016"),
        (["A-1", "A-2", "A-10"], "A-", 1, "A-11"),
    ],
)
def test_기존_번호를_이어받는다(existing, prefix, padding, expected):
    rule = numbering.infer_rule(existing)
    assert rule.prefix == prefix
    assert rule.padding == padding
    assert numbering.next_from(existing, rule) == expected


def test_번호_체계가_섞이면_많이_쓴_쪽을_따른다():
    mixed = [f"{i:04d}" for i in range(1, 50)] + ["LEGACY-1", "LEGACY-2"]
    rule = numbering.infer_rule(mixed)
    assert rule.prefix == ""
    assert numbering.next_from(mixed, rule) == "0050"


def test_읽을_규칙이_없으면_None():
    assert numbering.infer_rule([]) is None
    assert numbering.infer_rule(["번호없음", "ABC"]) is None


def test_자릿수를_넘기면_한_자리_늘어난다():
    rule = numbering.NumberingRule(prefix="", padding=4)
    assert numbering.next_from(["9999"], rule) == "10000"


# --- 실제 DB 로 다음 번호 --------------------------------------------------------

def test_자산이_없으면_기본_형식으로_시작한다(db):
    assert numbering.next_asset_no(db) == "0001"


def test_이관한_자산_뒤로_이어진다(db):
    db.add_all([Asset(asset_no=f"{i:04d}", name=f"자산{i}") for i in range(1, 122)])
    db.commit()
    assert numbering.next_asset_no(db) == "0122"


def test_이관한_사번_뒤로_이어진다(db):
    db.add_all([Employee(emp_no=f"E{i:04d}", name=f"직원{i}") for i in range(1, 104)])
    db.commit()
    assert numbering.next_employee_no(db) == "E0104"


def test_중간_번호가_비어_있어도_가장_큰_번호_다음을_쓴다(db):
    """번호를 재사용하면 예전 자산과 헷갈린다."""
    db.add_all([
        Asset(asset_no="0001", name="첫째"),
        Asset(asset_no="0005", name="다섯째"),
    ])
    db.commit()
    assert numbering.next_asset_no(db) == "0006"


def test_이미_쓰는_번호와_겹치면_건너뛴다(db):
    """직접 넣은 번호가 다음 자리를 차지하고 있을 수 있다."""
    db.add_all([
        Asset(asset_no="0001", name="첫째"),
        Asset(asset_no="0002", name="둘째"),
    ])
    db.commit()
    assert numbering.next_asset_no(db) == "0003"


# --- 설정 ---------------------------------------------------------------------

def test_자동_채번을_끄면_번호를_주지_않는다(db):
    set_value(db, "asset_no_auto", "0")
    db.commit()
    assert numbering.next_asset_no(db) is None
    assert numbering.next_employee_no(db) is not None   # 사번은 따로 동작한다


def test_접두사와_자릿수를_직접_정할_수_있다(db):
    db.add(Asset(asset_no="0001", name="기존"))
    numbering.save_rules(
        db,
        asset={"auto": True, "prefix": "IT-", "padding": 5},
        employee={"auto": True, "prefix": None, "padding": 0},
    )
    db.commit()

    # 직접 정한 접두사에는 아직 번호가 없으니 1번부터
    assert numbering.next_asset_no(db) == "IT-00001"


def test_자동_채번을_꺼도_정해_둔_형식은_남는다(db):
    """설정 화면에서 껐다 켜는 사이에 접두사가 사라지면 안 된다."""
    numbering.save_rules(
        db,
        asset={"auto": False, "prefix": "IT-", "padding": 5},
        employee={"auto": True, "prefix": None, "padding": 0},
    )
    db.commit()

    rule = numbering.asset_rule(db)
    assert rule.auto is False
    assert rule.prefix == "IT-" and rule.padding == 5
    assert numbering.next_asset_no(db) is None      # 꺼 둔 동안은 번호를 주지 않는다

    # 다시 켜면 정해 둔 형식 그대로 이어진다
    numbering.save_rules(
        db,
        asset={"auto": True, "prefix": "IT-", "padding": 5},
        employee={"auto": True, "prefix": None, "padding": 0},
    )
    db.commit()
    assert numbering.next_asset_no(db) == "IT-00001"


def test_자동_채번을_꺼도_설정_화면에_형식이_보인다(admin_client, db):
    numbering.save_rules(
        db,
        asset={"auto": False, "prefix": "IT-2026-", "padding": 4},
        employee={"auto": True, "prefix": None, "padding": 0},
    )
    db.commit()

    page = admin_client.get("/settings").text
    assert 'value="IT-2026-"' in page
    assert "자동 채번이 꺼져 있어" in page


def test_비워_두면_기존_번호_읽기로_돌아간다(db):
    db.add(Asset(asset_no="0007", name="기존"))
    numbering.save_rules(
        db,
        asset={"auto": True, "prefix": "IT-", "padding": 5},
        employee={"auto": True, "prefix": None, "padding": 0},
    )
    db.commit()
    assert numbering.next_asset_no(db) == "IT-00001"

    numbering.save_rules(
        db,
        asset={"auto": True, "prefix": None, "padding": 0},
        employee={"auto": True, "prefix": None, "padding": 0},
    )
    db.commit()
    assert numbering.next_asset_no(db) == "0008"
    assert get_text(db, "asset_no_prefix") is None


# --- 화면 --------------------------------------------------------------------

def test_자산_등록_화면에_번호가_미리_채워진다(admin_client, db):
    db.add_all([Asset(asset_no=f"{i:04d}", name=f"자산{i}") for i in range(1, 122)])
    db.commit()

    page = admin_client.get("/assets/new").text
    assert 'value="0122"' in page
    assert "자동으로 매겨졌습니다" in page


def test_직원_등록_화면에_사번이_미리_채워진다(admin_client, db):
    db.add_all([Employee(emp_no=f"E{i:04d}", name=f"직원{i}") for i in range(1, 104)])
    db.commit()

    page = admin_client.get("/employees/new").text
    assert 'value="E0104"' in page


def test_빠른_등록_팝업에도_사번이_채워진다(admin_client, db, asset):
    db.add(Employee(emp_no="E0009", name="기존"))
    db.commit()

    page = admin_client.get(f"/assets/{asset.id}").text
    assert 'value="E0010"' in page


def test_팝업으로_등록하면_다음_번호를_돌려준다(admin_client, db):
    """연달아 등록할 때 번호를 다시 매겨 주기 위해서다."""
    db.add(Employee(emp_no="E0009", name="기존"))
    db.commit()

    body = admin_client.post(
        "/employees/quick", data={"emp_no": "E0010", "name": "새사람", "status": "ACTIVE"}
    ).json()
    assert body["ok"] is True
    assert body["next_emp_no"] == "E0011"


def test_자동_채번을_끄면_번호_칸이_비어_있다(admin_client, db):
    set_value(db, "asset_no_auto", "0")
    db.commit()

    page = admin_client.get("/assets/new").text
    assert 'id="asset_no" name="asset_no" value=""' in page
    assert "자동으로 매겨졌습니다" not in page


def test_설정_화면에서_다음_번호를_미리_보여준다(admin_client, db):
    db.add(Asset(asset_no="0121", name="마지막"))
    db.commit()

    page = admin_client.get("/settings").text
    assert "0122" in page


def test_설정을_저장한다(admin_client, db):
    response = admin_client.post(
        "/settings",
        data={
            "asset_auto": "on", "asset_prefix": "IT-", "asset_padding": "5",
            "employee_auto": "on", "employee_prefix": "", "employee_padding": "",
        },
        follow_redirects=False,
    )
    assert response.status_code == 303

    db.expire_all()
    rule = numbering.asset_rule(db)
    assert rule.prefix == "IT-" and rule.padding == 5


def test_자릿수가_범위를_벗어나면_거부한다(admin_client):
    response = admin_client.post(
        "/settings",
        data={"asset_auto": "on", "asset_padding": "99",
              "employee_auto": "on", "employee_padding": ""},
    )
    assert response.status_code == 400
    assert "자릿수" in response.text


def test_기본값으로_되돌린다(admin_client, db):
    numbering.save_rules(
        db,
        asset={"auto": False, "prefix": "X", "padding": 7},
        employee={"auto": False, "prefix": "Y", "padding": 7},
    )
    db.commit()

    admin_client.post("/settings/reset", follow_redirects=False)
    db.expire_all()

    assert numbering.asset_rule(db).auto
    assert get_text(db, "asset_no_prefix") is None


def test_일반_사용자는_설정을_볼_수_없다(viewer_client):
    assert viewer_client.get("/settings").status_code == 403
    assert viewer_client.post("/settings", data={}).status_code == 403


def test_자동_채번된_번호로_실제_등록이_된다(admin_client, db):
    db.add_all([Asset(asset_no=f"{i:04d}", name=f"자산{i}") for i in range(1, 10)])
    db.commit()

    suggested = numbering.next_asset_no(db)
    assert suggested == "0010"

    response = admin_client.post(
        "/assets/new",
        data={"asset_no": suggested, "name": "새 자산", "category": "NOTEBOOK",
              "status": "IN_STOCK"},
        follow_redirects=False,
    )
    assert response.status_code == 303
    assert db.scalar(select(Asset).where(Asset.asset_no == "0010")) is not None

    # 다음 번호는 하나 더 올라간다
    db.expire_all()
    assert numbering.next_asset_no(db) == "0011"
