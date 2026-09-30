"""자동 채번 설정 (관리자 전용)."""

from fastapi import APIRouter, Request, status
from fastapi.responses import RedirectResponse

from app import forms, numbering
from app.deps import AdminUser, DbSession
from app.templating import flash, render

router = APIRouter(prefix="/settings", tags=["설정"])


def _view(db) -> dict:
    """현재 규칙과, 그 규칙으로 만들어질 다음 번호를 함께 보여준다."""
    return {
        "asset_rule": numbering.asset_rule(db),
        "employee_rule": numbering.employee_rule(db),
        "next_asset_no": numbering.next_asset_no(db),
        "next_employee_no": numbering.next_employee_no(db),
        "max_padding": numbering.MAX_PADDING,
    }


@router.get("")
def settings_form(request: Request, db: DbSession, user: AdminUser):
    return render(request, "settings.html", _view(db))


@router.post("")
async def save_settings(request: Request, db: DbSession, user: AdminUser):
    data = dict(await request.form())

    def read(field: str) -> dict:
        padding = forms.parse_int(data.get(f"{field}_padding")) or 0
        if padding and not 1 <= padding <= numbering.MAX_PADDING:
            raise ValueError(f"자릿수는 1 ~ {numbering.MAX_PADDING} 사이로 넣어 주세요.")
        return {
            "auto": data.get(f"{field}_auto") == "on",
            "prefix": forms.clean_str(data.get(f"{field}_prefix"), 30),
            "padding": padding,
        }

    try:
        asset = read("asset")
        employee = read("employee")
    except ValueError as exc:
        context = _view(db)
        context["error"] = str(exc)
        return render(request, "settings.html", context, status_code=status.HTTP_400_BAD_REQUEST)

    numbering.save_rules(db, asset=asset, employee=employee)
    db.commit()

    flash(request, "채번 설정을 저장했습니다.")
    return RedirectResponse("/settings", status_code=status.HTTP_303_SEE_OTHER)


@router.post("/reset")
def reset_settings(request: Request, db: DbSession, user: AdminUser):
    """직접 정한 형식을 지우고 '기존 번호에서 읽기'로 되돌린다."""
    numbering.save_rules(
        db,
        asset={"auto": True, "prefix": None, "padding": 0},
        employee={"auto": True, "prefix": None, "padding": 0},
    )
    db.commit()
    flash(request, "기존 번호를 따라가도록 되돌렸습니다.")
    return RedirectResponse("/settings", status_code=status.HTTP_303_SEE_OTHER)
