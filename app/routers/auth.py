"""로그인 / 로그아웃 / 비밀번호 변경 / 2단계 인증."""

from datetime import datetime, timedelta, timezone
from typing import Annotated
from urllib.parse import quote, urlparse

from fastapi import APIRouter, Depends, Form, Request, status
from fastapi.responses import RedirectResponse
from sqlalchemy import select

from app import config, labels, twofactor, useragent
from app.deps import CurrentUser, DbSession, get_current_user_optional, start_session
from app.models import User
from app.security import hash_password, validate_password, verify_password
from app.templating import flash, render

router = APIRouter(tags=["인증"])

# 비밀번호는 맞았지만 아직 2단계 인증이 남은 상태를 세션에 잠시 담아 둔다
PENDING_2FA_KEY = "pending_2fa_user_id"
# 2단계 인증을 받는 동안 '공용 PC' 선택을 잃지 않도록 함께 담아 둔다
PENDING_REMEMBER_KEY = "pending_remember"


def _safe_next(next_url: str | None) -> str:
    """오픈 리다이렉트를 막기 위해 같은 사이트 내 경로만 허용한다."""
    if not next_url:
        return "/"
    parsed = urlparse(next_url)
    if parsed.scheme or parsed.netloc or not next_url.startswith("/") or next_url.startswith("//"):
        return "/"
    return next_url


def _reopen_link(request: Request, target: str) -> str | None:
    """앱 안의 브라우저에서 열렸을 때, 같은 주소를 크롬으로 다시 여는 링크.

    카카오톡 등에서 QR 을 찍으면 앱 전용 브라우저가 열리고 로그인이 저장되지 않는다.
    안드로이드는 링크 한 번으로 크롬으로 넘길 수 있다.
    """
    agent = request.headers.get("user-agent")
    if not useragent.in_app_browser(agent) or not useragent.is_android(agent):
        return None
    return useragent.chrome_intent_url(str(request.base_url).rstrip("/") + target)


def _login_failed(db, user: User | None) -> None:
    """실패 횟수를 올리고, 너무 많이 틀리면 잠근다.

    계정이 없는 경우에는 아무 기록도 남기지 않는다. 아이디가 실제로 있는지를
    응답 차이로 알아낼 수 없어야 하기 때문이다.
    """
    if user is None:
        return
    user.failed_logins = (user.failed_logins or 0) + 1
    if user.failed_logins >= config.MAX_FAILED_LOGINS:
        user.locked_until = datetime.now(timezone.utc) + timedelta(
            seconds=config.LOGIN_LOCK_SECONDS
        )
        user.failed_logins = 0
    db.commit()


def _complete_login(
    request: Request, db, user: User, target: str, *, remember: bool = True
) -> RedirectResponse:
    """인증이 모두 끝났을 때 세션을 만들고 들여보낸다."""
    request.session.clear()
    start_session(request, user.id, remember=remember)
    user.last_login_at = datetime.now(timezone.utc)
    user.failed_logins = 0
    user.locked_until = None
    db.commit()

    flash(request, f"{user.name}님, 환영합니다.")
    return RedirectResponse(target, status_code=status.HTTP_303_SEE_OTHER)


@router.get("/login")
def login_form(
    request: Request,
    user: Annotated[User | None, Depends(get_current_user_optional)],
    next: str = "/",
):
    if user is not None:
        return RedirectResponse("/", status_code=status.HTTP_303_SEE_OTHER)
    target = _safe_next(next)
    return render(
        request,
        "login.html",
        {"next": target, "username": "", "reopen_url": _reopen_link(request, target)},
    )


@router.post("/login")
def login(
    request: Request,
    db: DbSession,
    username: Annotated[str, Form()],
    password: Annotated[str, Form()],
    next: Annotated[str, Form()] = "/",
    shared_device: Annotated[str | None, Form()] = None,
):
    target = _safe_next(next)
    # 공용 PC 라고 표시했을 때만 짧게 유지한다. 기본은 이 기기에서 계속 로그인 유지.
    remember = shared_device is None
    user = db.scalar(select(User).where(User.username == username.strip()))

    def deny(message: str, code: int):
        return render(
            request,
            "login.html",
            {
                "error": message,
                "username": username,
                "next": target,
                "reopen_url": _reopen_link(request, target),
                "shared_device": shared_device is not None,
            },
            status_code=code,
        )

    if user is not None and user.is_locked():
        minutes = max(1, round(user.lock_seconds_left() / 60))
        return deny(
            f"로그인 실패가 반복되어 계정이 잠겼습니다. {minutes}분 뒤에 다시 시도해 주세요.",
            status.HTTP_429_TOO_MANY_REQUESTS,
        )

    if user is None or not verify_password(password, user.password_hash):
        _login_failed(db, user)
        # 어느 쪽이 틀렸는지 알려주지 않는다.
        return deny("아이디 또는 비밀번호가 올바르지 않습니다.", status.HTTP_401_UNAUTHORIZED)

    if not user.is_active:
        return deny("비활성화된 계정입니다. 관리자에게 문의해 주세요.", status.HTTP_403_FORBIDDEN)

    if user.totp_enabled and user.totp_secret:
        # 비밀번호까지만 통과. 인증 코드를 넣어야 들어갈 수 있다.
        request.session.clear()
        request.session[PENDING_2FA_KEY] = user.id
        request.session[PENDING_REMEMBER_KEY] = remember
        return RedirectResponse(
            f"/login/2fa?next={quote(target, safe='/?=&')}",
            status_code=status.HTTP_303_SEE_OTHER,
        )

    return _complete_login(request, db, user, target, remember=remember)


@router.get("/login/2fa")
def two_factor_form(request: Request, next: str = "/"):
    if not request.session.get(PENDING_2FA_KEY):
        return RedirectResponse("/login", status_code=status.HTTP_303_SEE_OTHER)
    return render(request, "login_2fa.html", {"next": _safe_next(next)})


@router.post("/login/2fa")
def two_factor_verify(
    request: Request,
    db: DbSession,
    code: Annotated[str, Form()],
    next: Annotated[str, Form()] = "/",
):
    user_id = request.session.get(PENDING_2FA_KEY)
    if not user_id:
        return RedirectResponse("/login", status_code=status.HTTP_303_SEE_OTHER)

    user = db.get(User, user_id)
    if user is None or not user.is_active:
        request.session.clear()
        return RedirectResponse("/login", status_code=status.HTTP_303_SEE_OTHER)

    target = _safe_next(next)
    remember = bool(request.session.get(PENDING_REMEMBER_KEY, True))

    if twofactor.verify_code(user.totp_secret, code):
        return _complete_login(request, db, user, target, remember=remember)

    # 인증 앱을 쓸 수 없을 때를 위한 복구 코드도 받아 준다
    remaining = twofactor.use_recovery_code(user.recovery_codes, code)
    if remaining is not None:
        user.recovery_codes = remaining
        db.commit()
        response = _complete_login(request, db, user, target, remember=remember)
        left = twofactor.recovery_codes_left(remaining)
        message = f"복구 코드로 로그인했습니다. 남은 복구 코드는 {left}개입니다."
        if left <= 2:
            message += " 보안 설정에서 새로 발급해 주세요."
        flash(request, message, "warn")
        return response

    _login_failed(db, user)
    if user.is_locked():
        request.session.clear()
        return render(
            request,
            "login.html",
            {
                "error": "인증 실패가 반복되어 계정이 잠겼습니다. 잠시 뒤 다시 시도해 주세요.",
                "username": "",
                "next": target,
            },
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        )

    return render(
        request,
        "login_2fa.html",
        {"error": "인증 코드가 올바르지 않습니다.", "next": target},
        status_code=status.HTTP_401_UNAUTHORIZED,
    )


@router.post("/logout")
def logout(request: Request):
    request.session.clear()
    flash(request, "로그아웃되었습니다.")
    return RedirectResponse("/login", status_code=status.HTTP_303_SEE_OTHER)


# --- 내 계정 ------------------------------------------------------------------

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
        return render(
            request, "password.html", {"error": error}, status_code=status.HTTP_400_BAD_REQUEST
        )

    user.password_hash = hash_password(new_password)
    db.commit()
    flash(request, "비밀번호를 변경했습니다.")
    return RedirectResponse("/", status_code=status.HTTP_303_SEE_OTHER)


# --- 2단계 인증 설정 ------------------------------------------------------------

@router.get("/me/security")
def security_settings(request: Request, user: CurrentUser):
    return render(
        request,
        "security.html",
        {"codes_left": twofactor.recovery_codes_left(user.recovery_codes)},
    )


@router.get("/me/security/2fa")
def start_2fa(request: Request, db: DbSession, user: CurrentUser):
    """인증 앱 등록 화면. QR 을 띄워 준다."""
    if user.totp_enabled:
        return RedirectResponse("/me/security", status_code=status.HTTP_303_SEE_OTHER)

    # 등록을 마칠 때까지는 아직 켜지 않는다
    if not user.totp_secret:
        user.totp_secret = twofactor.new_secret()
        db.commit()

    uri = twofactor.provisioning_uri(user.totp_secret, user.username)
    return render(
        request,
        "security_2fa.html",
        {"secret": user.totp_secret, "qr_svg": labels.qr_svg(uri, box_size=4)},
    )


@router.post("/me/security/2fa")
def enable_2fa(
    request: Request,
    db: DbSession,
    user: CurrentUser,
    code: Annotated[str, Form()],
):
    if not user.totp_secret:
        return RedirectResponse("/me/security/2fa", status_code=status.HTTP_303_SEE_OTHER)

    if not twofactor.verify_code(user.totp_secret, code):
        uri = twofactor.provisioning_uri(user.totp_secret, user.username)
        return render(
            request,
            "security_2fa.html",
            {
                "secret": user.totp_secret,
                "qr_svg": labels.qr_svg(uri, box_size=4),
                "error": "인증 코드가 맞지 않습니다. 앱에 보이는 6자리를 다시 입력해 주세요.",
            },
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    codes, stored = twofactor.new_recovery_codes()
    user.totp_enabled = True
    user.recovery_codes = stored
    db.commit()

    # 복구 코드 원문은 이 화면에서 한 번만 보여준다
    return render(request, "security_codes.html", {"codes": codes, "first_time": True})


@router.post("/me/security/2fa/disable")
def disable_2fa(
    request: Request,
    db: DbSession,
    user: CurrentUser,
    password: Annotated[str, Form()],
):
    if not verify_password(password, user.password_hash):
        flash(request, "비밀번호가 올바르지 않아 2단계 인증을 끄지 못했습니다.", "error")
        return RedirectResponse("/me/security", status_code=status.HTTP_303_SEE_OTHER)

    user.totp_enabled = False
    user.totp_secret = None
    user.recovery_codes = None
    db.commit()
    flash(request, "2단계 인증을 껐습니다.", "warn")
    return RedirectResponse("/me/security", status_code=status.HTTP_303_SEE_OTHER)


@router.post("/me/security/recovery-codes")
def regenerate_recovery_codes(
    request: Request,
    db: DbSession,
    user: CurrentUser,
    password: Annotated[str, Form()],
):
    if not user.totp_enabled:
        return RedirectResponse("/me/security", status_code=status.HTTP_303_SEE_OTHER)

    if not verify_password(password, user.password_hash):
        flash(request, "비밀번호가 올바르지 않습니다.", "error")
        return RedirectResponse("/me/security", status_code=status.HTTP_303_SEE_OTHER)

    codes, stored = twofactor.new_recovery_codes()
    user.recovery_codes = stored
    db.commit()
    return render(request, "security_codes.html", {"codes": codes, "first_time": False})
