"""자산 지급 / 반납과 이력 조회."""

from datetime import date

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import RedirectResponse
from sqlalchemy import select
from sqlalchemy.orm import joinedload

from app import excel, forms
from app.deps import AdminUser, CurrentUser, DbSession
from app.models import ASSET_STATUSES, Asset, Assignment, Employee
from app.routers.assets import _xlsx_response
from app.services import (
    ASSIGNABLE_STATUSES,
    BusinessError,
    assign_asset,
    open_assignment,
    paginate,
    return_asset,
)
from app.templating import flash, render

router = APIRouter(prefix="/assignments", tags=["지급/반납"])


def _history_query(request: Request):
    params = request.query_params
    stmt = select(Assignment).options(
        joinedload(Assignment.asset), joinedload(Assignment.employee)
    )
    state = params.get("state")
    if state == "open":
        stmt = stmt.where(Assignment.returned_at.is_(None))
    elif state == "returned":
        stmt = stmt.where(Assignment.returned_at.is_not(None))

    employee_id = forms.parse_int(params.get("employee_id"))
    if employee_id:
        stmt = stmt.where(Assignment.employee_id == employee_id)

    asset_id = forms.parse_int(params.get("asset_id"))
    if asset_id:
        stmt = stmt.where(Assignment.asset_id == asset_id)

    keyword = (params.get("q") or "").strip()
    if keyword:
        like = f"%{keyword}%"
        stmt = stmt.where(
            Assignment.asset_id.in_(
                select(Asset.id).where(Asset.asset_no.ilike(like) | Asset.name.ilike(like))
            )
            | Assignment.employee_id.in_(
                select(Employee.id).where(Employee.name.ilike(like) | Employee.emp_no.ilike(like))
            )
        )
    return stmt.order_by(Assignment.assigned_at.desc(), Assignment.id.desc())


@router.get("")
def list_assignments(request: Request, db: DbSession, user: CurrentUser, page: int = 1):
    result = paginate(db, _history_query(request), page)
    employees = list(db.scalars(select(Employee).order_by(Employee.name)).all())
    return render(
        request,
        "assignments/list.html",
        {"page_obj": result, "employees": employees, "params": dict(request.query_params)},
    )


@router.get("/export")
def export_assignments(request: Request, db: DbSession, user: CurrentUser):
    items = list(db.scalars(_history_query(request)).unique().all())
    return _xlsx_response(excel.export_assignments(items), f"지급반납이력_{date.today():%Y%m%d}.xlsx")


@router.get("/new")
def assign_form(request: Request, db: DbSession, user: AdminUser, asset_id: int | None = None):
    assets = list(
        db.scalars(
            select(Asset)
            .where(Asset.holder_id.is_(None), Asset.status.in_(ASSIGNABLE_STATUSES))
            .order_by(Asset.asset_no)
        ).all()
    )
    employees = list(
        db.scalars(select(Employee).where(Employee.status != "RESIGNED").order_by(Employee.name)).all()
    )
    return render(
        request,
        "assignments/new.html",
        {"assets": assets, "employees": employees, "selected_asset_id": asset_id},
    )


@router.post("/new")
async def create_assignment(request: Request, db: DbSession, user: AdminUser):
    data = dict(await request.form())
    back_url = forms.clean_str(data.get("back_url")) or "/assignments"

    try:
        asset_id = forms.parse_int(data.get("asset_id"))
        employee_id = forms.parse_int(data.get("employee_id"))
        if not asset_id:
            raise BusinessError("지급할 자산을 선택해 주세요.")
        if not employee_id:
            raise BusinessError("지급받을 직원을 선택해 주세요.")

        asset = db.get(Asset, asset_id)
        employee = db.get(Employee, employee_id)
        if asset is None:
            raise BusinessError("선택한 자산을 찾을 수 없습니다.")
        if employee is None:
            raise BusinessError("선택한 직원을 찾을 수 없습니다.")

        assign_asset(
            db,
            asset=asset,
            employee=employee,
            assigned_at=forms.parse_date(data.get("assigned_at"), "지급일"),
            note=forms.clean_str(data.get("assigned_note")),
            actor=user.username,
        )
    except (BusinessError, ValueError) as exc:
        flash(request, str(exc), "error")
        return RedirectResponse(back_url, status_code=status.HTTP_303_SEE_OTHER)

    flash(request, f"[{asset.asset_no}] {asset.name} 을(를) {employee.name} 님에게 지급했습니다.")
    return RedirectResponse(f"/assets/{asset.id}", status_code=status.HTTP_303_SEE_OTHER)


@router.post("/{assignment_id}/return")
async def return_assignment(request: Request, db: DbSession, user: AdminUser, assignment_id: int):
    assignment = db.get(Assignment, assignment_id)
    if assignment is None:
        raise HTTPException(status_code=404, detail="지급 이력을 찾을 수 없습니다.")

    data = dict(await request.form())
    back_url = forms.clean_str(data.get("back_url")) or f"/assets/{assignment.asset_id}"

    try:
        return_asset(
            db,
            assignment=assignment,
            returned_at=forms.parse_date(data.get("returned_at"), "반납일"),
            new_status=forms.parse_choice(
                data.get("new_status"), ASSET_STATUSES, "반납 후 상태", "IN_STOCK"
            ),
            note=forms.clean_str(data.get("return_note")),
            actor=user.username,
        )
    except (BusinessError, ValueError) as exc:
        flash(request, str(exc), "error")
        return RedirectResponse(back_url, status_code=status.HTTP_303_SEE_OTHER)

    flash(
        request,
        f"[{assignment.asset.asset_no}] 자산을 {assignment.employee.name} 님으로부터 반납 처리했습니다.",
    )
    return RedirectResponse(back_url, status_code=status.HTTP_303_SEE_OTHER)
