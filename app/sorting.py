"""목록 표의 칸 제목을 눌러 정렬한다.

칸 제목을 한 번 누르면 오름차순(▲), 한 번 더 누르면 내림차순(▼)이다.
목록은 페이지로 나뉘어 있어서, 화면에 보이는 20건만 다시 늘어놓으면 틀린
결과가 된다. 그래서 정렬은 서버에서 전체를 대상으로 한다.

주소에는 이렇게 남는다.  /assets?sort=purchase_price&dir=desc
검색 조건과 함께 남으므로 그대로 북마크하거나 엑셀로 내려받을 수 있다.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Mapping

from sqlalchemy import case

ASC = "asc"
DESC = "desc"


@dataclass(frozen=True)
class SortColumn:
    """정렬할 수 있는 칸 하나.

    expressions: 정렬 기준이 되는 SQL 식(여러 개면 앞에서부터 차례로).
    default_desc: 주소에 방향이 없을 때 내림차순으로 볼지.
                  예전 주소(?sort=purchase_date)가 '최신이 위'였던 것을 지키기 위한 값이다.
    """

    expressions: tuple
    default_desc: bool = False


@dataclass
class Sort:
    key: str
    descending: bool
    columns: Mapping[str, SortColumn] = field(repr=False)

    @property
    def direction(self) -> str:
        return DESC if self.descending else ASC

    def order(self, stmt, *tiebreak):
        """정렬을 적용한다. 값이 비어 있는 행은 방향과 상관없이 맨 뒤로 보낸다."""
        column = self.columns[self.key]
        ordered = [
            (expr.desc() if self.descending else expr.asc()).nulls_last()
            for expr in column.expressions
        ]
        return stmt.order_by(*ordered, *tiebreak)

    # --- 화면에서 쓰는 값 ---------------------------------------------------------

    def state(self, key: str) -> str:
        """칸 제목의 aria-sort 값 (화면 읽기 프로그램용)."""
        if key != self.key:
            return "none"
        return "descending" if self.descending else "ascending"

    def next_direction(self, key: str) -> str:
        """그 칸 제목을 누르면 어느 방향이 되는지.

        지금 정렬 중인 칸이면 방향을 뒤집고, 다른 칸이면 오름차순부터 시작한다.
        """
        if key == self.key:
            return ASC if self.descending else DESC
        return ASC


def read_sort(
    params: Mapping[str, Any],
    columns: Mapping[str, SortColumn],
    default_key: str,
    *,
    default_desc: bool | None = None,
) -> Sort:
    """주소의 sort·dir 값을 읽는다. 모르는 값은 기본 정렬로 되돌린다."""
    key = params.get("sort") or default_key
    if key not in columns:
        key = default_key

    direction = params.get("dir")
    if direction in (ASC, DESC):
        descending = direction == DESC
    elif key == default_key and default_desc is not None:
        descending = default_desc
    else:
        descending = columns[key].default_desc

    return Sort(key=key, descending=descending, columns=columns)


def by_code_order(column, codes: Mapping[str, str]):
    """분류·상태처럼 코드로 저장된 값을, 화면의 목록 순서대로 정렬하는 식.

    코드의 알파벳 순서(DESKTOP, LOST, …)는 사람이 보기에 의미가 없다.
    검색 드롭다운에 나오는 순서(노트북, 데스크톱, 모니터 …)를 그대로 따른다.
    """
    return case(
        {code: index for index, code in enumerate(codes)},
        value=column,
        else_=len(codes),
    )
