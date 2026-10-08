"""Jinja2 템플릿 설정과 화면에서 쓰는 공통 필터/헬퍼."""

import hashlib
from datetime import date, datetime
from functools import lru_cache
from typing import Any
from urllib.parse import urlencode

from fastapi import Request
from fastapi.templating import Jinja2Templates

from app import config, models, useragent

templates = Jinja2Templates(directory=str(config.BASE_DIR / "templates"))

FLASH_KEY = "_flash"

# 화면 밝기. auto 는 컴퓨터·폰 설정을 따른다.
THEME_COOKIE = "theme"
THEMES = {"auto": "자동", "dark": "다크", "light": "라이트"}


def current_theme(request: Request) -> str:
    """쿠키에 적어 둔 화면 밝기. 처음이거나 값이 이상하면 auto."""
    value = request.cookies.get(THEME_COOKIE, "auto")
    return value if value in THEMES else "auto"


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


def url_with(request: Request, **overrides: Any) -> str:
    """지금 화면 주소에서 검색 조건 일부만 바꾼 주소.

    merge_query 는 조건이 하나도 안 남으면 빈 문자열을 돌려주는데, href="" 는
    '지금 주소 그대로'라서 조건이 풀리지 않는다. 그래서 경로를 앞에 붙인다.
    """
    return request.url.path + merge_query(request, **overrides)


# --- 정적 파일 주소 -------------------------------------------------------------
#
# 브라우저는 style.css 같은 파일을 한동안 저장해 두고 다시 받지 않는다. 서버를 업데이트해도
# 화면(HTML)만 새것이고 스타일은 예전 것이 섞여, 아이콘이 크게 그려지는 등 화면이 깨진다.
# 그래서 주소 뒤에 파일 내용의 지문(?v=…)을 붙인다. 파일이 바뀌면 주소가 바뀌어
# 브라우저가 반드시 새로 받고, 바뀌지 않았으면 저장해 둔 것을 오래 써도 된다.

STATIC_DIR = config.BASE_DIR / "static"


@lru_cache(maxsize=256)
def _fingerprint(path: str, mtime_ns: int) -> str:
    return hashlib.sha256((STATIC_DIR / path).read_bytes()).hexdigest()[:12]


def static_url(path: str) -> str:
    """/static 아래 파일 주소에 내용 지문을 붙인다.  static_url('css/style.css')"""
    file = STATIC_DIR / path
    try:
        version = _fingerprint(path, file.stat().st_mtime_ns)
    except OSError:
        return f"/static/{path}"
    return f"/static/{path}?v={version}"


templates.env.filters["date"] = fmt_date
templates.env.filters["datetime"] = fmt_datetime
templates.env.filters["money"] = fmt_money
templates.env.filters["input_date"] = fmt_input_date

# 자산 분류마다 붙는 아이콘 (static/icons/sprite.svg 의 이름).
# 목록을 훑어볼 때 글자를 읽기 전에 모양으로 먼저 알아보게 한다.
CATEGORY_ICONS = {
    "NOTEBOOK": "laptop",
    "DESKTOP": "desktop",
    "MONITOR": "monitor",
    "SERVER": "server",
    "NETWORK": "network",
    "MOBILE": "phone",
    "PERIPHERAL": "keyboard",
    "SOFTWARE": "code",
    "ETC": "tag",
}

templates.env.globals.update(
    APP_NAME="IT 자산관리 시스템",
    CATEGORY_ICONS=CATEGORY_ICONS,
    APP_VERSION="1.0.0",
    ASSET_CATEGORIES=models.ASSET_CATEGORIES,
    ASSET_STATUSES=models.ASSET_STATUSES,
    ASSIGNABLE_STATUSES=models.ASSIGNABLE_STATUSES,
    RETURN_STATUSES=models.RETURN_STATUSES,
    EMPLOYEE_STATUSES=models.EMPLOYEE_STATUSES,
    DEPRECIATION_METHODS=models.DEPRECIATION_METHODS,
    MAINTENANCE_KINDS=models.MAINTENANCE_KINDS,
    ROLES=models.ROLES,
    merge_query=merge_query,
    url_with=url_with,
    static_url=static_url,
    today=date.today,
)


# --- 플래시 메시지 -------------------------------------------------------------

def flash(request: Request, message: str, category: str = "success") -> None:
    """다음 화면에 한 번만 보여줄 안내 메시지를 세션에 담는다."""
    # 목록을 새로 만들어 다시 넣어야 한다. 이미 있는 목록에 append 만 하면
    # 세션이 '바뀌었다'는 것을 몰라서, 앞서 쌓인 문구가 있을 때 새 문구가 사라진다.
    messages = list(request.session.get(FLASH_KEY, []))
    messages.append({"message": message, "category": category})
    request.session[FLASH_KEY] = messages


def pop_flashes(request: Request) -> list[dict[str, str]]:
    return request.session.pop(FLASH_KEY, [])


def render(request: Request, template_name: str, context: dict[str, Any] | None = None, **kwargs: Any):
    """공통 컨텍스트(로그인 사용자, 플래시)를 채워 템플릿을 렌더링한다."""
    data: dict[str, Any] = {"request": request}
    data.update(context or {})
    data.setdefault("current_user", getattr(request.state, "user", None))
    # 카카오톡·네이버 앱 안의 브라우저는 로그인이 저장되지 않을 수 있어 안내한다
    data.setdefault(
        "in_app_browser", useragent.in_app_browser(request.headers.get("user-agent"))
    )
    # 서버가 처음부터 맞는 밝기로 그려 보내야, 새로 고칠 때 화면이 번쩍이지 않는다
    data.setdefault("theme", current_theme(request))
    data.setdefault("THEMES", THEMES)
    data["flashes"] = pop_flashes(request)
    return templates.TemplateResponse(request, template_name, data, **kwargs)
