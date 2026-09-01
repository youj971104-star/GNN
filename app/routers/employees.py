"""직원 등록 / 조회 / 수정 / 삭제."""

from datetime import date

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import RedirectResponse
from sqlalchemy import func, or_, select
from sqlalchemy.orm import joinedload, selectinload

from app import excel, forms
from app.deps import AdminUser, CurrentUser, DbSession
from app.models import EMPLOYEE_STATUSES, Asset, Assignment, Employee
from app.routers.assets import _xlsx_response
from app.services import paginate
from app.templating import flash, render

router = APIRouter(prefix="/employees", tags=["직원"])


def _get_employee(db: DbSession, employee_id: int) -> Employee:
    employee = db.get(Employee, employee_id)
    if employee is None:
        raise HTTPException(status_code=404, detail="요청하신 직원을 찾을 수 없습니다.")
    return employee


def _read_employee_form(data: dict, *, emp_no_required: bool = True) -> dict:
    values = {
        "name": forms.required_str(data.get("name"), "이름", 50),
        "department": forms.clean_str(data.get("department"), 50),
        "position": forms.clean_str(data.get("position"), 50),
        "email": forms.clean_str(data.get("email"), 120),
        "phone": forms.clean_str(data.get("phone"), 30),
        "status": forms.parse_choice(data.get("status"), EMPLOYEE_STATUSES, "재직상태", "ACTIVE"),
        "note": forms.clean_str(data.get("note")),
    }
    if emp_no_required:
        values["emp_no"] = forms.required_str(data.get("emp_no"), "사번", 30)
    if values["email"] and "@" not in values["email"]:
        raise ValueError("이메일 형식이 올바르지 않습니다.")
    return values


def _base_query(request: Request):
    """검색 조건이 적용된 직원 조회 쿼리."""
    params = request.query_params
    stmt = select(Employee)
    keyword = (params.get("q") or "").strip()
    if keyword:
        like = f"%{keyword}%"
        stmt = stmt.where(
            or_(
                Employee.name.ilike(like),
                Employee.emp_no.ilike(like),
                Employee.department.ilike(like),
                Employee.position.ilike(like),
                Employee.email.ilike(like),
            )
        )
    department = params.get("department")
    if department:
        stmt = stmt.where(Employee.department == department)
    emp_status = params.get("status")
    if emp_status:
        stmt = stmt.where(Employee.status == emp_status)
    return stmt.order_by(Employee.name, Employee.id)


@router.get("")
def list_employees(request: Request, db: DbSession, user: CurrentUser, page: int = 1):
    # 보유 자산 수를 함께 보여주므로 자산을 미리 읽는다.
    # joinedload 는 LIMIT 과 함께 쓰면 행이 부풀어 페이지네이션이 어긋나므로 selectinload 를 쓴다.
    stmt = _base_query(request).options(selectinload(Employee.assets))
    result = paginate(db, stmt, page)
    departments = [
        row
        for row in db.scalars(
            select(Employee.department).where(Employee.department.is_not(None)).distinct().order_by(Employee.department)
        ).all()
        if row
    ]
    return render(
        request,
        "employees/list.html",
        {"page_obj": result, "departments": departments, "params": dict(request.query_params)},
    )


@router.get("/new")
def new_employee_form(request: Request, user: AdminUser):
    return render(request, "employees/form.html", {"employee": None, "form": {"status": "ACTIVE"}})


@router.post("/new")
async def create_employee(request: Request, db: DbSession, user: AdminUser):
    data = dict(await request.form())
    try:
        values = _read_employee_form(data)
    except ValueError as exc:
        return render(
            request,
            "employees/form.html",
            {"employee": None, "form": data, "error": str(exc)},
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    if db.scalar(select(Employee).where(Employee.emp_no == values["emp_no"])):
        return render(
            request,
            "employees/form.html",
            {"employee": None, "form": data, "error": f"사번 '{values['emp_no']}'는 이미 등록되어 있습니다."},
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    employee = Employee(**values)
    db.add(employee)
    db.commit()
    db.refresh(employee)
    flash(request, f"직원 {employee.name}({employee.emp_no}) 을(를) 등록했습니다.")
    return RedirectResponse(f"/employees/{employee.id}", status_code=status.HTTP_303_SEE_OTHER)


@router.get("/export")
def export_employees(request: Request, db: DbSession, user: CurrentUser):
    employees = list(db.scalars(_base_query(request).options(selectinload(Employee.assets))).all())
    return _xlsx_response(excel.export_employees(employees), f"직원목록_{date.today():%Y%m%d}.xlsx")


@router.get("/{employee_id}")
def employee_detail(request: Request, db: DbSession, user: CurrentUser, employee_id: int):
    employee = _get_employee(db, employee_id)
    assets = list(
        db.scalars(select(Asset).where(Asset.holder_id == employee.id).order_by(Asset.asset_no)).all()
    )
    history = list(
        db.scalars(
            select(Assignment)
            .options(joinedload(Assignment.asset))
            .where(Assignment.employee_id == employee.id)
            .order_by(Assignment.assigned_at.desc(), Assignment.id.desc())
        ).all()
    )
    return render(
        request,
        "employees/detail.html",
        {"employee": employee, "assets": assets, "history": history},
    )


@router.get("/{employee_id}/edit")
def edit_employee_form(request: Request, db: DbSession, user: AdminUser, employee_id: int):
    employee = _get_employee(db, employee_id)
    return render(request, "employees/form.html", {"employee": employee, "form": None})


@router.post("/{employee_id}/edit")
async def update_employee(request: Request, db: DbSession, user: AdminUser, employee_id: int):
    employee = _get_employee(db, employee_id)
    data = dict(await request.form())
    try:
        values = _read_employee_form(data, emp_no_required=False)
    except ValueError as exc:
        return render(
            request,
            "employees/form.html",
            {"employee": employee, "form": data, "error": str(exc)},
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    holding = db.scalar(select(func.count(Asset.id)).where(Asset.holder_id == employee.id)) or 0
    if values["status"] == "RESIGNED" and holding:
        return render(
            request,
            "employees/form.html",
            {
                "employee": employee,
                "form": data,
                "error": f"보유 중인 자산이 {holding}건 있습니다. 반납 처리 후 퇴사로 변경해 주세요.",
            },
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    for key, value in values.items():
        setattr(employee, key, value)
    db.commit()
    flash(request, f"직원 {employee.name} 정보를 수정했습니다.")
    return RedirectResponse(f"/employees/{employee.id}", status_code=status.HTTP_303_SEE_OTHER)


@router.post("/{employee_id}/delete")
def delete_employee(request: Request, db: DbSession, user: AdminUser, employee_id: int):
    employee = _get_employee(db, employee_id)
    history_count = db.scalar(
        select(func.count(Assignment.id)).where(Assignment.employee_id == employee.id)
    ) or 0
    if history_count:
        flash(
            request,
            f"{employee.name} 님은 지급 이력이 {history_count}건 있어 삭제할 수 없습니다. "
            "대신 재직상태를 '퇴사'로 변경해 주세요.",
            "error",
        )
        return RedirectResponse(f"/employees/{employee.id}", status_code=status.HTTP_303_SEE_OTHER)

    name = employee.name
    db.delete(employee)
    db.commit()
    flash(request, f"직원 {name} 을(를) 삭제했습니다.")
    return RedirectResponse("/employees", status_code=status.HTTP_303_SEE_OTHER)
