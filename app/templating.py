"""Jinja2 템플릿 설정과 화면에서 쓰는 공통 필터/헬퍼."""

from datetime import date, datetime
from typing import Any
from urllib.parse import urlencode

from fastapi import Request
from fastapi.templating import Jinja2Templates

from app import config, models

templates = Jinja2Templates(directory=str(config.BASE_DIR / "templates"))

FLASH_KEY = "_flash"


# --- 필터 ---------------------------------------------------------------------

def fmt_date(value: date | datetime | None, fallback: str = "-") -> str:
    if value is None:
        return fallback
    return value.strftime("%Y-%m-%d")


def fmt_datetime(value: datetime | None, fallback: str = "-") -> str:
    if value is None:
        return fallback
    return value.strftime("%Y-%m-%d %H:%M")


def fmt_money(value: Any, fallback: str = "-") -> str:
    """1234567 -> '1,234,567'."""
    if value is None or value == "":
        return fallback
    try:
        return f"{int(round(float(value))):,}"
    except (TypeError, ValueError):
        return fallback


def fmt_input_date(value: date | None) -> str:
    """<input type="date"> 에 넣을 값."""
    return value.strftime("%Y-%m-%d") if value else ""


def merge_query(request: Request, **overrides: Any) -> str:
    """현재 화면의 검색조건을 유지한 채 일부만 바꾼 쿼리스트링을 만든다."""
    params = dict(request.query_params)
    for key, value in overrides.items():
        if value is None or value == "":
            params.pop(key, None)
        else:
            params[key] = str(value)
    return ("?" + urlencode(params)) if params else ""


templates.env.filters["date"] = fmt_date
templates.env.filters["datetime"] = fmt_datetime
templates.env.filters["money"] = fmt_money
templates.env.filters["input_date"] = fmt_input_date

templates.env.globals.update(
    APP_NAME="IT 자산관리 시스템",
    APP_VERSION="1.0.0",
    ASSET_CATEGORIES=models.ASSET_CATEGORIES,
    ASSET_STATUSES=models.ASSET_STATUSES,
    ASSIGNABLE_STATUSES=models.ASSIGNABLE_STATUSES,
    RETURN_STATUSES=models.RETURN_STATUSES,
    EMPLOYEE_STATUSES=models.EMPLOYEE_STATUSES,
    ROLES=models.ROLES,
    merge_query=merge_query,
    today=date.today,
)


# --- 플래시 메시지 -------------------------------------------------------------

def flash(request: Request, message: str, category: str = "success") -> None:
    """다음 화면에 한 번만 보여줄 안내 메시지를 세션에 담는다."""
    request.session.setdefault(FLASH_KEY, []).append(
        {"message": message, "category": category}
    )


def pop_flashes(request: Request) -> list[dict[str, str]]:
    return request.session.pop(FLASH_KEY, [])


def render(request: Request, template_name: str, context: dict[str, Any] | None = None, **kwargs: Any):
    """공통 컨텍스트(로그인 사용자, 플래시)를 채워 템플릿을 렌더링한다."""
    data: dict[str, Any] = {"request": request}
    data.update(context or {})
    data.setdefault("current_user", getattr(request.state, "user", None))
    data["flashes"] = pop_flashes(request)
    return templates.TemplateResponse(request, template_name, data, **kwargs)
