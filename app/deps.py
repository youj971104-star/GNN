"""공통 의존성 - 로그인 확인과 권한 검사."""

import time
from typing import Annotated

from fastapi import Depends, HTTPException, Request, status
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session

from app import config
from app.database import get_db
from app.models import User

SESSION_USER_KEY = "user_id"
# 이 세션을 얼마나 유지할지(초)와, 마지막으로 쓴 시각(epoch 초).
# 로그인할 때 '로그인 상태 유지' 를 어떻게 골랐는지가 세션마다 달라서 함께 담아 둔다.
SESSION_TTL_KEY = "ttl"
SESSION_SEEN_KEY = "seen"

# 마지막 사용 시각을 매 요청마다 고쳐 쓸 필요는 없다. 이 간격으로만 갱신한다.
SEEN_REFRESH_SECONDS = 60


def now_seconds() -> int:
    """현재 시각(epoch 초). 테스트에서 시간을 앞으로 돌리기 위해 따로 둔다."""
    return int(time.time())


def start_session(request: Request, user_id: int, *, remember: bool = True) -> None:
    """로그인이 끝났을 때 세션을 만든다.

    remember 가 False 면(공용 PC) 짧게 유지하고, 기본은 30일간 유지한다.
    폰으로 QR 라벨을 찍을 때마다 로그인하는 일을 막기 위한 것이다.
    """
    request.session[SESSION_USER_KEY] = user_id
    request.session[SESSION_TTL_KEY] = (
        config.SESSION_MAX_AGE if remember else config.SHORT_SESSION_MAX_AGE
    )
    request.session[SESSION_SEEN_KEY] = now_seconds()


def session_user_id(request: Request) -> int | None:
    """세션에 담긴 사용자 id. 유지 시간이 지났으면 세션을 비우고 None 을 준다.

    유지 시간은 '마지막으로 쓴 시점'부터 세므로, 계속 쓰는 동안에는 풀리지 않는다.
    """
    if "session" not in request.scope:
        return None

    user_id = request.session.get(SESSION_USER_KEY)
    if not user_id:
        return None

    ttl = int(request.session.get(SESSION_TTL_KEY) or config.SESSION_MAX_AGE)
    seen = int(request.session.get(SESSION_SEEN_KEY) or 0)
    now = now_seconds()

    if seen and now - seen > ttl:
        request.session.clear()
        return None

    if now - seen >= SEEN_REFRESH_SECONDS:
        request.session[SESSION_SEEN_KEY] = now
    return user_id


class LoginRequired(Exception):
    """로그인이 필요한 화면에 비로그인 상태로 접근한 경우."""

    def __init__(self, next_url: str = "/"):
        self.next_url = next_url


def get_current_user_optional(
    request: Request, db: Annotated[Session, Depends(get_db)]
) -> User | None:
    """세션에 담긴 사용자. 없으면 None (로그인 화면 등에서 사용)."""
    user_id = session_user_id(request)
    if not user_id:
        return None
    user = db.get(User, user_id)
    if user is None or not user.is_active:
        request.session.clear()
        return None
    return user


def get_current_user(
    request: Request,
    user: Annotated[User | None, Depends(get_current_user_optional)],
) -> User:
    """로그인한 사용자. 비로그인이면 로그인 화면으로 보낸다."""
    if user is None:
        # 검색 조건 등 쿼리스트링까지 살려 두어야 로그인 후 같은 화면으로 돌아온다
        target = request.url.path
        if request.url.query:
            target = f"{target}?{request.url.query}"
        raise LoginRequired(next_url=target)
    return user


def require_admin(user: Annotated[User, Depends(get_current_user)]) -> User:
    """관리자 전용 화면/동작에 사용."""
    if not user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="이 작업은 관리자만 수행할 수 있습니다.",
        )
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]
AdminUser = Annotated[User, Depends(require_admin)]
DbSession = Annotated[Session, Depends(get_db)]


def login_redirect(next_url: str = "/") -> RedirectResponse:
    from urllib.parse import quote

    target = "/login"
    if next_url and next_url != "/":
        target = f"/login?next={quote(next_url, safe='')}"
    return RedirectResponse(target, status_code=status.HTTP_303_SEE_OTHER)
