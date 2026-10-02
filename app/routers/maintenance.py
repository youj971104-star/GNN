"""자산 정비(수리·점검) 이력."""

from datetime import date

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import RedirectResponse
from sqlalchemy import func, select
from sqlalchemy.orm import joinedload

from app import excel, forms
from app.deps import AdminUser, CurrentUser, DbSession
from app.models import MAINTENANCE_KINDS, Asset, Maintenance
from app.routers.assets import _xlsx_response
from app.services import paginate
from app.sorting import SortColumn, by_code_order, read_sort
from app.templating import flash, render

router = APIRouter(prefix="/maintenance", tags=["정비"])


def _asset_field(column):
    return select(column).where(Asset.id == Maintenance.asset_id).correlate(Maintenance).scalar_subquery()


# 칸 제목을 눌러 정렬할 수 있는 칸들
SORT_COLUMNS = {
    "maintained_at": SortColumn((Maintenance.maintained_at,), default_desc=True),
    "asset_no": SortColumn((_asset_field(Asset.asset_no),)),
    "asset_name": SortColumn((_asset_field(Asset.name),)),
    "kind": SortColumn((by_code_order(Maintenance.kind, MAINTENANCE_KINDS),)),
    "vendor": SortColumn((Maintenance.vendor,)),
    "description": SortColumn((Maintenance.description,)),
    "cost": SortColumn((Maintenance.cost,), default_desc=True),
    "next_due": SortColumn((Maintenance.next_due,)),
}


def _sort(request: Request):
    # 기본은 예전과 같이 최근 정비가 위
    return read_sort(request.query_params, SORT_COLUMNS, "maintained_at", default_desc=True)


def _history_query(request: Request):
    params = request.query_params
    stmt = select(Maintenance).options(joinedload(Maintenance.asset))

    kind = params.get("kind")
    if kind:
        stmt = stmt.where(Maintenance.kind == kind)

    asset_id = forms.parse_int(params.get("asset_id"))
    if asset_id:
        stmt = stmt.where(Maintenance.asset_id == asset_id)

    keyword = (params.get("q") or "").strip()
    if keyword:
        like = f"%{keyword}%"
        stmt = stmt.where(
            Maintenance.description.ilike(like)
            | Maintenance.vendor.ilike(like)
            | Maintenance.asset_id.in_(
                select(Asset.id).where(Asset.asset_no.ilike(like) | Asset.name.ilike(like))
            )
        )

    if params.get("due") == "1":
        # 다음 점검 예정일이 지났거나 30일 안에 돌아오는 건
        stmt = stmt.where(Maintenance.next_due.is_not(None))

    return _sort(request).order(stmt, Maintenance.maintained_at.desc(), Maintenance.id.desc())


def _read_form(data: dict) -> dict:
    values = {
        "maintained_at": forms.parse_date(data.get("maintained_at"), "정비일") or date.today(),
        "kind": forms.parse_choice(data.get("kind"), MAINTENANCE_KINDS, "정비 종류", "REPAIR"),
        "vendor": forms.clean_str(data.get("vendor"), 80),
        "description": forms.required_str(data.get("description"), "작업 내용"),
        "cost": forms.parse_money(data.get("cost"), "비용"),
        "next_due": forms.parse_date(data.get("next_due"), "다음 점검 예정일"),
    }
    if values["maintained_at"] > date.today():
        raise ValueError("정비일은 오늘 이후 날짜로 지정할 수 없습니다.")
    if values["next_due"] and values["next_due"] < values["maintained_at"]:
        raise ValueError("다음 점검 예정일은 정비일보다 빠를 수 없습니다.")
    return values


@router.get("")
def list_maintenance(request: Request, db: DbSession, user: CurrentUser, page: int = 1):
    result = paginate(db, _history_query(request), page)
    total_cost = db.scalar(
        select(func.coalesce(func.sum(Maintenance.cost), 0))
    ) or 0
    return render(
        request,
        "maintenance/list.html",
        {
            "page_obj": result,
            "params": dict(request.query_params),
            "total_cost": float(total_cost),
            "sort": _sort(request),
        },
    )


@router.get("/export")
def export_maintenance(request: Request, db: DbSession, user: CurrentUser):
    items = list(db.scalars(_history_query(request)).unique().all())
    return _xlsx_response(excel.export_maintenance(items), f"정비이력_{date.today():%Y%m%d}.xlsx")


@router.post("/new")
async def create_maintenance(request: Request, db: DbSession, user: AdminUser):
    data = dict(await request.form())
    asset_id = forms.parse_int(data.get("asset_id"))
    asset = db.get(Asset, asset_id) if asset_id else None
    if asset is None:
        raise HTTPException(status_code=404, detail="자산을 찾을 수 없습니다.")

    back_url = forms.clean_str(data.get("back_url")) or f"/assets/{asset.id}"
    try:
        values = _read_form(data)
    except ValueError as exc:
        flash(request, str(exc), "error")
        return RedirectResponse(back_url, status_code=status.HTTP_303_SEE_OTHER)

    db.add(Maintenance(asset_id=asset.id, created_by=user.username, **values))

    # 수리 기록을 남기면서 자산을 '수리중'으로 돌릴 수 있게 한다
    if data.get("set_repairing") == "on" and asset.holder_id is None:
        asset.status = "REPAIR"

    db.commit()
    flash(request, f"[{asset.asset_no}] 정비 이력을 등록했습니다.")
    return RedirectResponse(back_url, status_code=status.HTTP_303_SEE_OTHER)


@router.post("/{maintenance_id}/delete")
async def delete_maintenance(
    request: Request, db: DbSession, user: AdminUser, maintenance_id: int
):
    item = db.get(Maintenance, maintenance_id)
    if item is None:
        raise HTTPException(status_code=404, detail="정비 이력을 찾을 수 없습니다.")

    data = dict(await request.form())
    back_url = forms.clean_str(data.get("back_url")) or f"/assets/{item.asset_id}"
    db.delete(item)
    db.commit()
    flash(request, "정비 이력을 삭제했습니다.")
    return RedirectResponse(back_url, status_code=status.HTTP_303_SEE_OTHER)
