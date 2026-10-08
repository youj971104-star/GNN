"""어느 화면에서든 쓰는 전체 검색.

위쪽 막대의 검색칸(키보드 / )에 무엇을 넣든 여기로 온다.

- 자산번호나 사번을 정확히 넣으면(라벨 QR 주소를 붙여 넣어도) 그 화면으로 바로 간다.
- 아니면 자산과 직원에서 함께 찾아 한 화면에 보여 준다.
"""

from fastapi import APIRouter, Request, status
from fastapi.responses import RedirectResponse
from sqlalchemy import func, or_, select
from sqlalchemy.orm import selectinload

from app import scanning
from app.deps import CurrentUser, DbSession
from app.models import Asset, Employee
from app.services import AssetFilter, paginate, search_assets
from app.templating import render

router = APIRouter(tags=["검색"])

PREVIEW_SIZE = 10


def _exact_target(db, q: str) -> str | None:
    """정확히 하나를 가리키는 값이면 그 화면 주소."""
    code = scanning.parse_scanned_code(q)
    if code:
        asset_id = db.scalar(select(Asset.id).where(func.lower(Asset.asset_no) == code.lower()))
        if asset_id:
            return f"/assets/{asset_id}"
    asset_id = scanning.parse_asset_id(q)
    if asset_id and db.get(Asset, asset_id):
        return f"/assets/{asset_id}"
    employee_id = db.scalar(select(Employee.id).where(func.lower(Employee.emp_no) == q.lower()))
    if employee_id:
        return f"/employees/{employee_id}"
    return None


@router.get("/search")
def search(request: Request, db: DbSession, user: CurrentUser, q: str = ""):
    q = q.strip()[:100]
    if not q:
        return RedirectResponse("/assets", status_code=status.HTTP_303_SEE_OTHER)

    target = _exact_target(db, q)
    if target:
        return RedirectResponse(target, status_code=status.HTTP_303_SEE_OTHER)

    assets = search_assets(db, AssetFilter(q=q), page=1, size=PREVIEW_SIZE)

    like = f"%{q}%"
    employee_stmt = (
        select(Employee)
        .options(selectinload(Employee.assets))
        .where(
            or_(
                Employee.name.ilike(like),
                Employee.emp_no.ilike(like),
                Employee.department.ilike(like),
                Employee.position.ilike(like),
                Employee.email.ilike(like),
                Employee.phone.ilike(like),
            )
        )
        .order_by(Employee.status, Employee.name, Employee.id)
    )
    employees = paginate(db, employee_stmt, 1, PREVIEW_SIZE)

    return render(
        request,
        "search.html",
        {"q": q, "search_q": q, "assets": assets, "employees": employees},
    )
