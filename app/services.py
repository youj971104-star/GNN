"""검색/집계/지급·반납 등 화면 뒤에서 도는 업무 로직."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, timedelta

from sqlalchemy import Select, func, or_, select
from sqlalchemy.orm import Session, joinedload

from app import config
from app.models import (
    ASSET_CATEGORIES,
    ASSET_STATUSES,
    ASSIGNABLE_STATUSES,
    Asset,
    Assignment,
    Employee,
)


class BusinessError(Exception):
    """사용자에게 그대로 보여줄 수 있는 업무 규칙 위반."""


# --- 자산 검색 ----------------------------------------------------------------

@dataclass
class AssetFilter:
    """자산 목록 화면의 검색 조건."""

    q: str | None = None
    category: str | None = None
    status: str | None = None
    department: str | None = None
    holder_id: int | None = None
    unassigned: bool = False
    sort: str = "asset_no"

    SORTS: dict[str, str] = field(
        default_factory=lambda: {
            "asset_no": "자산번호",
            "name": "자산명",
            "purchase_date": "도입일",
            "purchase_price": "취득가액",
            "updated_at": "최근 수정일",
        },
        repr=False,
    )

    def apply(self, stmt: Select) -> Select:
        if self.q:
            keyword = f"%{self.q.strip()}%"
            stmt = stmt.where(
                or_(
                    Asset.asset_no.ilike(keyword),
                    Asset.name.ilike(keyword),
                    Asset.model_name.ilike(keyword),
                    Asset.serial_no.ilike(keyword),
                    Asset.manufacturer.ilike(keyword),
                    Asset.location.ilike(keyword),
                    Asset.note.ilike(keyword),
                )
            )
        if self.category:
            stmt = stmt.where(Asset.category == self.category)
        if self.status:
            stmt = stmt.where(Asset.status == self.status)
        if self.holder_id:
            stmt = stmt.where(Asset.holder_id == self.holder_id)
        if self.unassigned:
            stmt = stmt.where(Asset.holder_id.is_(None))
        if self.department:
            stmt = stmt.where(
                Asset.holder_id.in_(
                    select(Employee.id).where(Employee.department == self.department)
                )
            )
        return stmt

    def order(self, stmt: Select) -> Select:
        column = {
            "asset_no": Asset.asset_no,
            "name": Asset.name,
            "purchase_date": Asset.purchase_date,
            "purchase_price": Asset.purchase_price,
            "updated_at": Asset.updated_at,
        }.get(self.sort, Asset.asset_no)
        # 도입일/취득가액/수정일은 최신·큰 값이 위로 오는 편이 자연스럽다.
        if self.sort in ("purchase_date", "purchase_price", "updated_at"):
            return stmt.order_by(column.desc().nullslast(), Asset.asset_no)
        return stmt.order_by(column, Asset.id)

    @property
    def is_active(self) -> bool:
        return any([self.q, self.category, self.status, self.department, self.holder_id, self.unassigned])


@dataclass
class Page:
    """페이지네이션 결과."""

    items: list
    total: int
    page: int
    size: int

    @property
    def pages(self) -> int:
        return max(1, (self.total + self.size - 1) // self.size)

    @property
    def has_prev(self) -> bool:
        return self.page > 1

    @property
    def has_next(self) -> bool:
        return self.page < self.pages

    @property
    def start_index(self) -> int:
        return 0 if self.total == 0 else (self.page - 1) * self.size + 1

    @property
    def end_index(self) -> int:
        return min(self.page * self.size, self.total)

    def page_range(self, window: int = 2) -> list[int]:
        start = max(1, self.page - window)
        end = min(self.pages, self.page + window)
        return list(range(start, end + 1))


def paginate(db: Session, stmt: Select, page: int, size: int | None = None) -> Page:
    size = size or config.PAGE_SIZE
    page = max(1, page)
    total = db.scalar(select(func.count()).select_from(stmt.order_by(None).subquery())) or 0
    # unique() 는 joinedload 로 같은 행이 여러 번 나오는 경우를 정리한다.
    items = list(db.scalars(stmt.limit(size).offset((page - 1) * size)).unique().all())
    return Page(items=items, total=total, page=page, size=size)


def search_assets(db: Session, filters: AssetFilter, page: int = 1, size: int | None = None) -> Page:
    stmt = filters.order(filters.apply(select(Asset).options(joinedload(Asset.holder))))
    return paginate(db, stmt, page, size)


def all_matching_assets(db: Session, filters: AssetFilter) -> list[Asset]:
    """페이지네이션 없이 조건에 맞는 전체 자산 (엑셀 다운로드용)."""
    stmt = filters.order(filters.apply(select(Asset).options(joinedload(Asset.holder))))
    return list(db.scalars(stmt).all())


def departments(db: Session) -> list[str]:
    """등록된 부서 목록 (검색 필터용)."""
    rows = db.scalars(
        select(Employee.department)
        .where(Employee.department.is_not(None))
        .distinct()
        .order_by(Employee.department)
    ).all()
    return [row for row in rows if row]


# --- 지급 / 반납 --------------------------------------------------------------

def open_assignment(db: Session, asset_id: int) -> Assignment | None:
    """해당 자산의 미반납 지급 건."""
    return db.scalar(
        select(Assignment)
        .where(Assignment.asset_id == asset_id, Assignment.returned_at.is_(None))
        .order_by(Assignment.assigned_at.desc(), Assignment.id.desc())
    )


def assign_asset(
    db: Session,
    *,
    asset: Asset,
    employee: Employee,
    assigned_at: date | None = None,
    note: str | None = None,
    actor: str | None = None,
) -> Assignment:
    """자산을 직원에게 지급하고 이력을 남긴다."""
    if open_assignment(db, asset.id) is not None:
        raise BusinessError(
            f"[{asset.asset_no}] 자산은 이미 지급 중입니다. 먼저 반납 처리해 주세요."
        )
    if asset.status not in ASSIGNABLE_STATUSES:
        raise BusinessError(
            f"'{ASSET_STATUSES.get(asset.status, asset.status)}' 상태의 자산은 지급할 수 없습니다."
        )
    if employee.status == "RESIGNED":
        raise BusinessError(f"퇴사한 직원({employee.name})에게는 자산을 지급할 수 없습니다.")

    assigned_at = assigned_at or date.today()
    if assigned_at > date.today():
        raise BusinessError("지급일은 오늘 이후 날짜로 지정할 수 없습니다.")

    assignment = Assignment(
        asset_id=asset.id,
        employee_id=employee.id,
        assigned_at=assigned_at,
        assigned_note=note,
        created_by=actor,
    )
    asset.status = "IN_USE"
    asset.holder_id = employee.id
    db.add(assignment)
    db.commit()
    db.refresh(assignment)
    return assignment


def return_asset(
    db: Session,
    *,
    assignment: Assignment,
    returned_at: date | None = None,
    new_status: str = "IN_STOCK",
    note: str | None = None,
    actor: str | None = None,
) -> Assignment:
    """지급 건을 반납 처리하고 자산 상태를 되돌린다."""
    if not assignment.is_open:
        raise BusinessError("이미 반납 처리된 이력입니다.")

    returned_at = returned_at or date.today()
    if returned_at < assignment.assigned_at:
        raise BusinessError("반납일은 지급일보다 빠를 수 없습니다.")
    if returned_at > date.today():
        raise BusinessError("반납일은 오늘 이후 날짜로 지정할 수 없습니다.")
    if new_status not in ASSET_STATUSES:
        raise BusinessError("반납 후 자산 상태 값이 올바르지 않습니다.")

    assignment.returned_at = returned_at
    assignment.return_note = note
    assignment.returned_by = actor

    asset = assignment.asset
    asset.status = new_status
    asset.holder_id = None
    db.commit()
    db.refresh(assignment)
    return assignment


# --- 대시보드 집계 -------------------------------------------------------------

WARRANTY_SOON_DAYS = 90


def dashboard_stats(db: Session, today: date | None = None) -> dict:
    """대시보드 화면에 필요한 통계를 한 번에 모은다."""
    today = today or date.today()

    total = db.scalar(select(func.count(Asset.id))) or 0

    status_rows = db.execute(
        select(Asset.status, func.count(Asset.id)).group_by(Asset.status)
    ).all()
    status_counts = {code: 0 for code in ASSET_STATUSES}
    for code, count in status_rows:
        status_counts[code] = count

    category_rows = db.execute(
        select(Asset.category, func.count(Asset.id), func.coalesce(func.sum(Asset.purchase_price), 0))
        .group_by(Asset.category)
        .order_by(func.count(Asset.id).desc())
    ).all()
    by_category = [
        {
            "code": code,
            "label": ASSET_CATEGORIES.get(code, code),
            "count": count,
            "amount": float(amount or 0),
        }
        for code, count, amount in category_rows
    ]

    dept_rows = db.execute(
        select(Employee.department, func.count(Asset.id))
        .join(Asset, Asset.holder_id == Employee.id)
        .group_by(Employee.department)
        .order_by(func.count(Asset.id).desc())
    ).all()
    by_department = [
        {"label": dept or "(부서 미지정)", "count": count} for dept, count in dept_rows
    ]

    total_amount = float(db.scalar(select(func.coalesce(func.sum(Asset.purchase_price), 0))) or 0)
    employee_count = db.scalar(select(func.count(Employee.id)).where(Employee.status != "RESIGNED")) or 0

    warranty_soon = list(
        db.scalars(
            select(Asset)
            .options(joinedload(Asset.holder))
            .where(
                Asset.warranty_until.is_not(None),
                Asset.warranty_until <= today + timedelta(days=WARRANTY_SOON_DAYS),
                Asset.status.not_in(("DISPOSED", "LOST")),
            )
            .order_by(Asset.warranty_until)
            .limit(10)
        ).all()
    )

    recent_assignments = list(
        db.scalars(
            select(Assignment)
            .options(joinedload(Assignment.asset), joinedload(Assignment.employee))
            .order_by(Assignment.created_at.desc(), Assignment.id.desc())
            .limit(8)
        ).all()
    )

    long_held = list(
        db.scalars(
            select(Assignment)
            .options(joinedload(Assignment.asset), joinedload(Assignment.employee))
            .join(Employee, Assignment.employee_id == Employee.id)
            .where(Assignment.returned_at.is_(None), Employee.status == "RESIGNED")
            .order_by(Assignment.assigned_at)
        ).all()
    )

    max_category = max((row["count"] for row in by_category), default=0)
    max_department = max((row["count"] for row in by_department), default=0)

    return {
        "total": total,
        "status_counts": status_counts,
        "by_category": by_category,
        "by_department": by_department,
        "max_category": max_category,
        "max_department": max_department,
        "total_amount": total_amount,
        "employee_count": employee_count,
        "assigned_count": status_counts.get("IN_USE", 0),
        "warranty_soon": warranty_soon,
        "recent_assignments": recent_assignments,
        "resigned_holding": long_held,
        "warranty_days": WARRANTY_SOON_DAYS,
    }
