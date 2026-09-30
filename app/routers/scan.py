"""사이트 안에서 QR 을 연속으로 찍는 화면.

폰 카메라 앱으로 라벨을 찍으면 찍을 때마다 새 창이 열린다. 여러 대를
확인할 때는 번거롭다. 여기서는 로그인한 화면 그대로 카메라를 열어,
창을 옮기지 않고 계속 찍는다.

브라우저가 카메라를 열어 주려면 HTTPS 여야 한다(주소가 http 면 막힌다).
"""

from fastapi import APIRouter, Request
from sqlalchemy import select

from app import scanning
from app.deps import CurrentUser, DbSession
from app.models import ASSET_CATEGORIES, ASSET_STATUSES, Asset
from app.services import open_assignment
from app.templating import render

router = APIRouter(tags=["스캔"])


@router.get("/scan")
def scan_page(request: Request, user: CurrentUser):
    return render(request, "scan.html", {})


@router.get("/scan/lookup")
def scan_lookup(request: Request, db: DbSession, user: CurrentUser, code: str = ""):
    """찍은 값으로 자산 하나를 찾아 화면에 보여줄 내용을 돌려준다."""
    asset = None

    asset_no = scanning.parse_scanned_code(code)
    if asset_no:
        asset = db.scalar(select(Asset).where(Asset.asset_no == asset_no))

    if asset is None:
        asset_id = scanning.parse_asset_id(code)
        if asset_id is not None:
            asset = db.get(Asset, asset_id)

    if asset is None:
        return {
            "ok": False,
            "code": code.strip(),
            "error": f"'{(asset_no or code).strip()}' 에 해당하는 자산이 없습니다.",
        }

    current = open_assignment(db, asset.id)
    holder = None
    if current is not None and current.employee is not None:
        holder = {
            "name": current.employee.name,
            "emp_no": current.employee.emp_no,
            "department": current.employee.department or "",
            "since": current.assigned_at.strftime("%Y-%m-%d") if current.assigned_at else "",
        }

    return {
        "ok": True,
        "id": asset.id,
        "asset_no": asset.asset_no,
        "name": asset.name,
        "category": ASSET_CATEGORIES.get(asset.category, asset.category or ""),
        "status": ASSET_STATUSES.get(asset.status, asset.status or ""),
        "status_code": asset.status,
        "model": asset.model_name or "",
        "serial_no": asset.serial_no or "",
        "location": asset.location or "",
        "holder": holder,
        # 화면에서 바로 이어서 할 수 있는 작업.
        # 지급·반납 양식은 자산 상세 화면에 있으므로 그 칸으로 바로 보낸다.
        "detail_url": f"/assets/{asset.id}",
        "action_url": f"/assets/{asset.id}#assign",
        "action_label": "반납 처리" if current is not None else "지급 처리",
        "can_manage": user.is_admin,
    }
