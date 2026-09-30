"""화면에서 바꿀 수 있는 설정값 보관소.

환경변수(app/config.py)는 서버를 다시 띄워야 바뀌므로, 운영 중에 관리자가
바꿔야 하는 값은 DB 에 둔다. 값은 모두 문자열로 저장하고 읽을 때 형변환한다.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Setting


def get_text(db: Session, key: str, default: str | None = None) -> str | None:
    row = db.get(Setting, key)
    if row is None or row.value is None:
        return default
    return row.value


def get_bool(db: Session, key: str, default: bool = False) -> bool:
    value = get_text(db, key, None)
    if value is None:
        return default
    return value == "1"


def get_int(db: Session, key: str, default: int = 0) -> int:
    value = get_text(db, key, None)
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        return default


def set_value(db: Session, key: str, value: str | None) -> None:
    """값을 저장한다. None 이면 '정하지 않음'으로 비워 둔다."""
    row = db.get(Setting, key)
    if row is None:
        row = Setting(key=key)
        db.add(row)
    row.value = value


def all_values(db: Session) -> dict[str, str | None]:
    return {row.key: row.value for row in db.scalars(select(Setting)).all()}
