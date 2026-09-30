"""자산번호와 사번 자동 채번.

기본 방침은 **이미 쓰고 있는 번호 뒤에 이어 붙이는 것**이다.
회사마다 번호 체계가 달라서 형식을 정해 놓으면 맞지 않는다.
그래서 기존 번호에서 '접두사 + 숫자' 꼴을 읽어내고 숫자만 하나 올린다.

    0121      → 0122
    E0103     → E0104
    IT-2026-0015 → IT-2026-0016

형식을 직접 정하고 싶으면 설정 화면에서 접두사와 자릿수를 지정할 수 있다.
"""

from __future__ import annotations

import re
from collections import Counter
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Asset, Employee
from app.settings_store import get_bool, get_int, get_text, set_value

# 번호 끝에 붙은 연속된 숫자를 떼어 낸다
_TAIL_DIGITS = re.compile(r"^(.*?)(\d+)$")

DEFAULT_PADDING = 4
MAX_PADDING = 12


@dataclass
class NumberingRule:
    """한 종류(자산번호 / 사번)의 채번 규칙."""

    auto: bool = True
    prefix: str = ""
    padding: int = DEFAULT_PADDING

    def format(self, value: int) -> str:
        return f"{self.prefix}{value:0{self.padding}d}"


# 설정 저장소에 쓰는 키
ASSET_KEYS = ("asset_no_auto", "asset_no_prefix", "asset_no_padding")
EMPLOYEE_KEYS = ("employee_no_auto", "employee_no_prefix", "employee_no_padding")


def split_number(value: str) -> tuple[str, str] | None:
    """'E0103' → ('E', '0103'). 끝에 숫자가 없으면 None."""
    match = _TAIL_DIGITS.match((value or "").strip())
    if not match:
        return None
    return match.group(1), match.group(2)


def infer_rule(existing: list[str]) -> NumberingRule | None:
    """기존 번호들에서 접두사와 자릿수를 읽어낸다.

    번호 체계가 섞여 있을 수 있으므로, 가장 많이 쓰인 접두사를 기준으로 삼는다.
    끝에 숫자가 없는 번호는 규칙을 읽을 수 없어 셈에서 뺀다.
    """
    parsed = [split_number(value) for value in existing]
    usable = [item for item in parsed if item is not None]
    if not usable:
        return None

    prefix, _ = Counter(prefix for prefix, _ in usable).most_common(1)[0]
    same_prefix = [digits for item_prefix, digits in usable if item_prefix == prefix]

    # 자릿수도 가장 흔한 값을 따른다 (9999 를 넘겨 10000 이 섞여도 흔들리지 않는다)
    padding = Counter(len(digits) for digits in same_prefix).most_common(1)[0][0]
    return NumberingRule(auto=True, prefix=prefix, padding=min(padding, MAX_PADDING))


def next_from(existing: list[str], rule: NumberingRule) -> str:
    """규칙에 맞는 기존 번호들 다음 값."""
    highest = 0
    for value in existing:
        item = split_number(value)
        if item is None:
            continue
        prefix, digits = item
        if prefix == rule.prefix:
            highest = max(highest, int(digits))

    candidate = highest + 1
    # 자릿수를 넘기면 자연스럽게 한 자리 늘어난다 (9999 → 10000)
    return rule.format(candidate)


# --- 설정 읽고 쓰기 -------------------------------------------------------------

def _load_rule(db: Session, keys: tuple[str, str, str], existing: list[str]) -> NumberingRule:
    auto_key, prefix_key, padding_key = keys

    stored_prefix = get_text(db, prefix_key, None)
    stored_padding = get_int(db, padding_key, 0)

    # 따로 정해 둔 값이 없으면 기존 번호에서 읽어낸다
    if stored_prefix is None and not stored_padding:
        rule = infer_rule(existing) or NumberingRule()
    else:
        rule = NumberingRule(
            prefix=stored_prefix or "",
            padding=stored_padding or DEFAULT_PADDING,
        )

    # 자동 채번을 꺼도 정해 둔 형식은 남겨 둔다.
    # 그러지 않으면 설정 화면에서 껐다 켜는 사이에 접두사가 사라진다.
    rule.auto = get_bool(db, auto_key, True)
    return rule


def _all_asset_numbers(db: Session) -> list[str]:
    return [value for value in db.scalars(select(Asset.asset_no)).all() if value]


def _all_employee_numbers(db: Session) -> list[str]:
    return [value for value in db.scalars(select(Employee.emp_no)).all() if value]


def asset_rule(db: Session) -> NumberingRule:
    return _load_rule(db, ASSET_KEYS, _all_asset_numbers(db))


def employee_rule(db: Session) -> NumberingRule:
    return _load_rule(db, EMPLOYEE_KEYS, _all_employee_numbers(db))


def _next_unused(existing: list[str], rule: NumberingRule) -> str:
    """이미 쓰고 있는 번호와 겹치지 않는 다음 값.

    번호를 건너뛰며 직접 넣은 경우가 있어, 겹치면 하나씩 올려 본다.
    """
    taken = set(existing)
    candidate = next_from(existing, rule)

    item = split_number(candidate)
    value = int(item[1]) if item else 1
    while candidate in taken:
        value += 1
        candidate = rule.format(value)
    return candidate


def next_asset_no(db: Session) -> str | None:
    """다음 자산번호. 자동 채번을 꺼 두었으면 None."""
    rule = asset_rule(db)
    if not rule.auto:
        return None
    return _next_unused(_all_asset_numbers(db), rule)


def next_employee_no(db: Session) -> str | None:
    """다음 사번. 자동 채번을 꺼 두었으면 None."""
    rule = employee_rule(db)
    if not rule.auto:
        return None
    return _next_unused(_all_employee_numbers(db), rule)


def save_rules(db: Session, *, asset: dict, employee: dict) -> None:
    """설정 화면에서 넘어온 값을 저장한다."""
    for keys, values in ((ASSET_KEYS, asset), (EMPLOYEE_KEYS, employee)):
        auto_key, prefix_key, padding_key = keys
        set_value(db, auto_key, "1" if values.get("auto") else "0")

        # 비워 두면 '기존 번호에서 읽어내기'로 돌아간다
        prefix = values.get("prefix")
        set_value(db, prefix_key, prefix if prefix not in (None, "") else None)

        padding = values.get("padding") or 0
        set_value(db, padding_key, str(padding) if padding else None)
