"""로그인 / 로그아웃 / 비밀번호 변경."""

from datetime import datetime, timezone
from typing import Annotated
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, Form, Request, status
from fastapi.responses import RedirectResponse
from sqlalchemy import select

from app.deps import SESSION_USER_KEY, CurrentUser, DbSession, get_current_user_optional
from app.models import User
from app.security import hash_password, validate_password, verify_password
from app.templating import flash, render

router = APIRouter(tags=["인증"])


def _safe_next(next_url: str | None) -> str:
    """오픈 리다이렉트를 막기 위해 같은 사이트 내 경로만 허용한다."""
    if not next_url:
        return "/"
    parsed = urlparse(next_url)
    if parsed.scheme or parsed.netloc or not next_url.startswith("/") or next_url.startswith("//"):
        return "/"
    return next_url


@router.get("/login")
def login_form(
    request: Request,
    user: Annotated[User | None, Depends(get_current_user_optional)],
    next: str = "/",
):
    if user is not None:
        return RedirectResponse("/", status_code=status.HTTP_303_SEE_OTHER)
    return render(request, "login.html", {"next": _safe_next(next), "username": ""})


@router.post("/login")
def login(
    request: Request,
    db: DbSession,
    username: Annotated[str, Form()],
    password: Annotated[str, Form()],
    next: Annotated[str, Form()] = "/",
):
    target = _safe_next(next)
    user = db.scalar(select(User).where(User.username == username.strip()))

    if user is None or not verify_password(password, user.password_hash):
        # 어느 쪽이 틀렸는지 알려주지 않는다.
        return render(
            request,
            "login.html",
            {
                "error": "아이디 또는 비밀번호가 올바르지 않습니다.",
                "username": username,
                "next": target,
            },
            status_code=status.HTTP_401_UNAUTHORIZED,
        )

    if not user.is_active:
        return render(
            request,
            "login.html",
            {
                "error": "비활성화된 계정입니다. 관리자에게 문의해 주세요.",
                "username": username,
                "next": target,
            },
            status_code=status.HTTP_403_FORBIDDEN,
        )

    request.session.clear()
    request.session[SESSION_USER_KEY] = user.id
    user.last_login_at = datetime.now(timezone.utc)
    db.commit()

    flash(request, f"{user.name}님, 환영합니다.")
    return RedirectResponse(target, status_code=status.HTTP_303_SEE_OTHER)


@router.post("/logout")
def logout(request: Request):
    request.session.clear()
    flash(request, "로그아웃되었습니다.")
    return RedirectResponse("/login", status_code=status.HTTP_303_SEE_OTHER)


@router.get("/me/password")
def password_form(request: Request, user: CurrentUser):
    return render(request, "password.html", {})


@router.post("/me/password")
def change_password(
    request: Request,
    db: DbSession,
    user: CurrentUser,
    current_password: Annotated[str, Form()],
    new_password: Annotated[str, Form()],
    confirm_password: Annotated[str, Form()],
):
    error: str | None = None
    if not verify_password(current_password, user.password_hash):
        error = "현재 비밀번호가 올바르지 않습니다."
    elif new_password != confirm_password:
        error = "새 비밀번호와 확인 값이 서로 다릅니다."
    else:
        error = validate_password(new_password)

    if error:
        return render(request, "password.html", {"error": error}, status_code=status.HTTP_400_BAD_REQUEST)

    user.password_hash = hash_password(new_password)
    db.commit()
    flash(request, "비밀번호를 변경했습니다.")
    return RedirectResponse("/", status_code=status.HTTP_303_SEE_OTHER)
