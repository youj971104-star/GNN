"""가벼운 스키마 이전(마이그레이션).

이미 운영 중인 DB 에 새 컬럼이 생겼을 때, 데이터를 건드리지 않고 컬럼만 덧붙인다.
새 테이블은 create_all 이 만들어 주므로 여기서는 '기존 테이블의 빠진 컬럼'만 다룬다.

Alembic 같은 본격 도구를 쓰지 않는 이유는, 이 프로그램의 스키마 변경이
'컬럼 추가'에 그치고 되돌릴 일이 거의 없기 때문이다. 복잡한 변경이 필요해지면
그때 Alembic 을 도입하는 편이 낫다.
"""

from __future__ import annotations

from sqlalchemy import Engine, inspect, text
from sqlalchemy.schema import Column

from app.database import Base


def _column_ddl(column: Column, dialect) -> str | None:
    """ALTER TABLE ADD COLUMN 에 쓸 조각을 만든다.

    값을 반드시 채워야 하는(NOT NULL) 컬럼은 기존 행을 채울 방법이 없어 건너뛴다.
    """
    if not column.nullable and column.default is None and column.server_default is None:
        return None

    type_sql = column.type.compile(dialect=dialect)
    ddl = f"{column.name} {type_sql}"
    if column.server_default is not None:
        ddl += f" DEFAULT {column.server_default.arg}"
    return ddl


def pending_columns(engine: Engine) -> list[tuple[str, Column]]:
    """모델에는 있는데 DB 에는 없는 컬럼 목록."""
    inspector = inspect(engine)
    existing_tables = set(inspector.get_table_names())

    missing: list[tuple[str, Column]] = []
    for table in Base.metadata.sorted_tables:
        if table.name not in existing_tables:
            continue  # 새 테이블은 create_all 이 통째로 만든다
        db_columns = {info["name"] for info in inspector.get_columns(table.name)}
        for column in table.columns:
            if column.name not in db_columns:
                missing.append((table.name, column))
    return missing


def _fixed_default(column: Column):
    """모델에 정해진 고정 기본값. 함수로 만드는 값(현재 시각 등)은 대상이 아니다."""
    default = column.default
    if default is None or getattr(default, "is_callable", False):
        return None
    return getattr(default, "arg", None)


def apply_pending_migrations(engine: Engine) -> list[str]:
    """빠진 컬럼을 추가하고, 적용한 내용을 문자열 목록으로 돌려준다."""
    applied: list[str] = []
    skipped: list[str] = []

    for table_name, column in pending_columns(engine):
        ddl = _column_ddl(column, engine.dialect)
        if ddl is None:
            skipped.append(f"{table_name}.{column.name}")
            continue

        with engine.begin() as connection:
            connection.execute(text(f"ALTER TABLE {table_name} ADD COLUMN {ddl}"))

            # 컬럼을 덧붙이면 기존 행은 빈 값(NULL)이 된다.
            # 모델에 기본값이 정해져 있으면 그 값으로 채워, 새로 만든 행과 같게 맞춘다.
            # (안 맞춰 두면 "꺼짐"을 찾는 조건 검색에서 기존 행이 빠진다)
            fill = _fixed_default(column)
            if fill is not None:
                connection.execute(
                    text(f"UPDATE {table_name} SET {column.name} = :value"
                         f" WHERE {column.name} IS NULL"),
                    {"value": fill},
                )

        applied.append(f"{table_name}.{column.name}")

    if applied:
        print(f"[스키마 이전] 컬럼을 추가했습니다: {', '.join(applied)}")
    if skipped:
        print(
            "[스키마 이전] 자동으로 추가하지 못한 컬럼이 있습니다: "
            f"{', '.join(skipped)} (비어 있을 수 없는 컬럼입니다)"
        )
    return applied
