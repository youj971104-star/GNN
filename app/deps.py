"""공통 의존성 - 로그인 확인과 권한 검사."""

from typing import Annotated

from fastapi import Depends, HTTPException, Request, status
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User

SESSION_USER_KEY = "user_id"


class LoginRequired(Exception):
    """로그인이 필요한 화면에 비로그인 상태로 접근한 경우."""

    def __init__(self, next_url: str = "/"):
        self.next_url = next_url


def get_current_user_optional(
    request: Request, db: Annotated[Session, Depends(get_db)]
) -> User | None:
    """세션에 담긴 사용자. 없으면 None (로그인 화면 등에서 사용)."""
    user_id = request.session.get(SESSION_USER_KEY)
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
        raise LoginRequired(next_url=str(request.url.path))
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
