"""자산 등록 / 조회 / 수정 / 삭제 + 엑셀 업로드·다운로드."""

import urllib.parse
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Form, HTTPException, Request, UploadFile, status
from fastapi.responses import RedirectResponse, Response
from sqlalchemy import select
from sqlalchemy.orm import joinedload

from app import config, excel, forms, labels, numbering
from app.deps import AdminUser, CurrentUser, DbSession
from app.models import (
    ASSET_CATEGORIES,
    ASSET_STATUSES,
    DEFAULT_USEFUL_LIFE,
    DEPRECIATION_METHODS,
    Asset,
    Assignment,
    Employee,
    Maintenance,
)
from app.services import AssetFilter, all_matching_assets, departments, open_assignment, search_assets
from app.templating import flash, render

router = APIRouter(prefix="/assets", tags=["자산"])


def _xlsx_response(content: bytes, filename: str) -> Response:
    """한글 파일명이 깨지지 않도록 RFC 5987 형식으로 내려준다."""
    quoted = urllib.parse.quote(filename)
    return Response(
        content=content,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f"attachment; filename*=UTF-8''{quoted}"},
    )


def _filter_from_query(request: Request) -> AssetFilter:
    params = request.query_params
    return AssetFilter(
        q=params.get("q") or None,
        category=params.get("category") or None,
        status=params.get("status") or None,
        department=params.get("department") or None,
        holder_id=forms.parse_int(params.get("holder_id")),
        unassigned=params.get("unassigned") == "1",
        sort=params.get("sort") or "asset_no",
        direction=params.get("dir"),
    )


def _get_asset(db: DbSession, asset_id: int) -> Asset:
    asset = db.get(Asset, asset_id)
    if asset is None:
        raise HTTPException(status_code=404, detail="요청하신 자산을 찾을 수 없습니다.")
    return asset


def _employee_choices(db: DbSession) -> list[Employee]:
    return list(
        db.scalars(
            select(Employee).where(Employee.status != "RESIGNED").order_by(Employee.name)
        ).all()
    )


def _read_asset_form(data: dict, *, asset_no_required: bool = True) -> dict:
    """자산 등록/수정 폼을 검증해 모델에 넣을 값으로 바꾼다."""
    values = {
        "name": forms.required_str(data.get("name"), "자산명", 120),
        "category": forms.parse_choice(data.get("category"), ASSET_CATEGORIES, "분류", "ETC"),
        "status": forms.parse_choice(data.get("status"), ASSET_STATUSES, "상태", "IN_STOCK"),
        "manufacturer": forms.clean_str(data.get("manufacturer"), 60),
        "model_name": forms.clean_str(data.get("model_name"), 120),
        "serial_no": forms.clean_str(data.get("serial_no"), 120),
        "spec": forms.clean_str(data.get("spec")),
        "location": forms.clean_str(data.get("location"), 80),
        "supplier": forms.clean_str(data.get("supplier"), 80),
        "purchase_date": forms.parse_date(data.get("purchase_date"), "도입일"),
        "purchase_price": forms.parse_money(data.get("purchase_price"), "취득가액"),
        "warranty_until": forms.parse_date(data.get("warranty_until"), "보증만료일"),
        "license_key": forms.clean_str(data.get("license_key"), 255),
        "note": forms.clean_str(data.get("note")),
        "depreciation_method": forms.parse_choice(
            data.get("depreciation_method"), DEPRECIATION_METHODS, "상각방법", "NONE"
        ),
        "useful_life_years": forms.parse_int(data.get("useful_life_years")),
        "salvage_value": forms.parse_money(data.get("salvage_value"), "잔존가치"),
    }
    if asset_no_required:
        values["asset_no"] = forms.required_str(data.get("asset_no"), "자산번호", 50)

    if values["purchase_date"] and values["warranty_until"]:
        if values["warranty_until"] < values["purchase_date"]:
            raise ValueError("보증만료일은 도입일보다 빠를 수 없습니다.")
    if values["purchase_date"] and values["purchase_date"] > date.today():
        raise ValueError("도입일은 오늘 이후 날짜로 지정할 수 없습니다.")

    if values["depreciation_method"] != "NONE":
        if not values["useful_life_years"] or values["useful_life_years"] <= 0:
            raise ValueError("감가상각을 쓰려면 내용연수를 1년 이상으로 입력해 주세요.")
        if not values["purchase_price"]:
            raise ValueError("감가상각을 쓰려면 취득가액이 필요합니다.")
        if not values["purchase_date"]:
            raise ValueError("감가상각을 쓰려면 도입일이 필요합니다.")
        if values["salvage_value"] and values["salvage_value"] > values["purchase_price"]:
            raise ValueError("잔존가치는 취득가액보다 클 수 없습니다.")
    return values



# --- 목록 / 상세 ---------------------------------------------------------------

@router.get("")
def list_assets(request: Request, db: DbSession, user: CurrentUser, page: int = 1):
    filters = _filter_from_query(request)
    result = search_assets(db, filters, page=page)
    return render(
        request,
        "assets/list.html",
        {
            "page_obj": result,
            "filters": filters,
            "departments": departments(db),
            "employees": _employee_choices(db),
        },
    )


@router.get("/new")
def new_asset_form(request: Request, db: DbSession, user: AdminUser):
    suggested = numbering.next_asset_no(db)
    return render(
        request,
        "assets/form.html",
        {
            "asset": None,
            # 자동 채번이 꺼져 있으면 비워 두고 직접 입력받는다
            "form": {
                "asset_no": suggested or "",
                "status": "IN_STOCK",
                "category": "NOTEBOOK",
            },
            "auto_numbered": suggested is not None,
            "default_useful_life": DEFAULT_USEFUL_LIFE,
        },
    )


@router.post("/new")
async def create_asset(request: Request, db: DbSession, user: AdminUser):
    data = dict(await request.form())
    try:
        values = _read_asset_form(data)
    except ValueError as exc:
        return render(
            request,
            "assets/form.html",
            {"asset": None, "form": data, "error": str(exc)},
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    if db.scalar(select(Asset).where(Asset.asset_no == values["asset_no"])):
        return render(
            request,
            "assets/form.html",
            {"asset": None, "form": data, "error": f"자산번호 '{values['asset_no']}'는 이미 등록되어 있습니다."},
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    asset = Asset(**values)
    db.add(asset)
    db.commit()
    db.refresh(asset)
    flash(request, f"자산 [{asset.asset_no}] {asset.name} 을(를) 등록했습니다.")
    return RedirectResponse(f"/assets/{asset.id}", status_code=status.HTTP_303_SEE_OTHER)


@router.get("/export")
def export_assets(request: Request, db: DbSession, user: CurrentUser):
    """현재 검색 조건이 그대로 반영된 엑셀을 내려받는다."""
    filters = _filter_from_query(request)
    assets = all_matching_assets(db, filters)
    filename = f"자산목록_{date.today():%Y%m%d}.xlsx"
    return _xlsx_response(excel.export_assets(assets), filename)


@router.get("/template")
def download_template(request: Request, user: AdminUser):
    return _xlsx_response(excel.export_asset_template(), "자산등록_양식.xlsx")


@router.get("/import")
def import_form(request: Request, user: AdminUser):
    return render(request, "assets/import.html", {"result": None})


@router.post("/import")
async def import_assets(request: Request, db: DbSession, user: AdminUser, file: UploadFile):
    if not (file.filename or "").lower().endswith((".xlsx", ".xlsm")):
        return render(
            request,
            "assets/import.html",
            {"result": None, "error": "엑셀 파일(.xlsx)만 올릴 수 있습니다."},
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    content = await file.read()
    if len(content) > config.MAX_UPLOAD_BYTES:
        limit_mb = config.MAX_UPLOAD_BYTES // (1024 * 1024)
        return render(
            request,
            "assets/import.html",
            {"result": None, "error": f"파일이 너무 큽니다. {limit_mb}MB 이하로 올려 주세요."},
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    result = excel.import_assets(db, content, actor=user.username)
    if result.total_processed and not result.has_errors:
        flash(request, result.summary())
        return RedirectResponse("/assets", status_code=status.HTTP_303_SEE_OTHER)
    return render(request, "assets/import.html", {"result": result})


@router.get("/labels")
def print_labels(request: Request, db: DbSession, user: CurrentUser):
    """현재 검색 조건에 맞는 자산들의 QR 라벨 인쇄 화면."""
    filters = _filter_from_query(request)
    assets = all_matching_assets(db, filters)

    # QR 에는 이 서버의 주소를 그대로 담는다. 폰으로 찍으면 바로 열린다.
    base = str(request.base_url).rstrip("/")
    items = [
        {"asset": asset, "qr": labels.qr_svg(base + labels.short_path(asset.asset_no))}
        for asset in assets[: config.MAX_LABELS_PER_PRINT]
    ]
    return render(
        request,
        "assets/labels.html",
        {
            "items": items,
            "filters": filters,
            "total": len(assets),
            "limit": config.MAX_LABELS_PER_PRINT,
        },
    )


@router.get("/{asset_id}")
def asset_detail(request: Request, db: DbSession, user: CurrentUser, asset_id: int):
    asset = _get_asset(db, asset_id)
    history = list(
        db.scalars(
            select(Assignment)
            .options(joinedload(Assignment.employee))
            .where(Assignment.asset_id == asset.id)
            .order_by(Assignment.assigned_at.desc(), Assignment.id.desc())
        ).all()
    )
    maintenances = list(
        db.scalars(
            select(Maintenance)
            .where(Maintenance.asset_id == asset.id)
            .order_by(Maintenance.maintained_at.desc(), Maintenance.id.desc())
        ).all()
    )
    base = str(request.base_url).rstrip("/")
    return render(
        request,
        "assets/detail.html",
        {
            "asset": asset,
            "history": history,
            "maintenances": maintenances,
            "current": open_assignment(db, asset.id),
            "employees": _employee_choices(db),
            # 직원 빠른 등록 팝업에 쓰는 값
            "modal_departments": departments(db),
            "modal_next_emp_no": numbering.next_employee_no(db),
            "qr_svg": labels.qr_svg(base + labels.short_path(asset.asset_no), box_size=3),
            "qr_target": base + labels.short_path(asset.asset_no),
        },
    )


@router.get("/{asset_id}/edit")
def edit_asset_form(request: Request, db: DbSession, user: AdminUser, asset_id: int):
    asset = _get_asset(db, asset_id)
    return render(request, "assets/form.html", {"asset": asset, "form": None})


@router.post("/{asset_id}/edit")
async def update_asset(request: Request, db: DbSession, user: AdminUser, asset_id: int):
    asset = _get_asset(db, asset_id)
    data = dict(await request.form())
    try:
        values = _read_asset_form(data, asset_no_required=False)
    except ValueError as exc:
        return render(
            request,
            "assets/form.html",
            {"asset": asset, "form": data, "error": str(exc)},
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    # 지급 중인 자산의 상태는 지급/반납 화면에서만 바꾼다.
    if asset.holder_id is not None and values["status"] != "IN_USE":
        return render(
            request,
            "assets/form.html",
            {
                "asset": asset,
                "form": data,
                "error": "지급 중인 자산입니다. 상태를 바꾸려면 먼저 반납 처리해 주세요.",
            },
            status_code=status.HTTP_400_BAD_REQUEST,
        )
    if asset.holder_id is None and values["status"] == "IN_USE":
        return render(
            request,
            "assets/form.html",
            {
                "asset": asset,
                "form": data,
                "error": "'사용중' 상태는 직원에게 지급할 때 자동으로 설정됩니다.",
            },
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    for key, value in values.items():
        setattr(asset, key, value)
    db.commit()
    flash(request, f"자산 [{asset.asset_no}] 정보를 수정했습니다.")
    return RedirectResponse(f"/assets/{asset.id}", status_code=status.HTTP_303_SEE_OTHER)


@router.post("/{asset_id}/delete")
def delete_asset(request: Request, db: DbSession, user: AdminUser, asset_id: int):
    asset = _get_asset(db, asset_id)
    if open_assignment(db, asset.id) is not None:
        flash(request, "지급 중인 자산은 삭제할 수 없습니다. 먼저 반납 처리해 주세요.", "error")
        return RedirectResponse(f"/assets/{asset.id}", status_code=status.HTTP_303_SEE_OTHER)

    label = f"[{asset.asset_no}] {asset.name}"
    db.delete(asset)  # 지급 이력도 함께 삭제된다 (cascade)
    db.commit()
    flash(request, f"자산 {label} 을(를) 삭제했습니다.")
    return RedirectResponse("/assets", status_code=status.HTTP_303_SEE_OTHER)
