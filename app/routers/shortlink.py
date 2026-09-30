"""QR 라벨이 가리키는 짧은 주소.

폰 카메라로 QR 을 찍으면 이 주소가 열리고, 해당 자산 상세 화면으로 넘겨준다.
QR 에 담기는 값이라 짧을수록 좋아서 /a/<자산번호> 형태를 쓴다.
"""

from fastapi import APIRouter, Request, status
from fastapi.responses import RedirectResponse
from sqlalchemy import select

from app.deps import CurrentUser, DbSession
from app.models import Asset
from app.templating import flash

router = APIRouter(tags=["QR"])


@router.get("/a/{asset_no}")
def open_asset_by_number(
    request: Request, db: DbSession, user: CurrentUser, asset_no: str
):
    asset = db.scalar(select(Asset).where(Asset.asset_no == asset_no))
    if asset is None:
        flash(request, f"자산번호 '{asset_no}' 를 찾을 수 없습니다.", "error")
        return RedirectResponse("/assets", status_code=status.HTTP_303_SEE_OTHER)
    return RedirectResponse(f"/assets/{asset.id}", status_code=status.HTTP_303_SEE_OTHER)
