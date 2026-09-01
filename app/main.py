"""애플리케이션 진입점."""

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exception_handlers import http_exception_handler
from fastapi.staticfiles import StaticFiles
from sqlalchemy import select
from starlette.middleware.sessions import SessionMiddleware

from app import config
from app.database import SessionLocal, init_db
from app.deps import SESSION_USER_KEY, LoginRequired, login_redirect
from app.models import User
from app.routers import assets, assignments, auth, dashboard, employees, users
from app.security import hash_password
from app.templating import render


def ensure_default_admin() -> None:
    """관리자 계정이 하나도 없으면 기본 관리자 계정을 만든다.

    일반 사용자 계정만 남은 상태에서도 다시 로그인할 수 있도록,
    '계정이 있는지'가 아니라 '관리자가 있는지'로 판단한다.
    """
    with SessionLocal() as db:
        existing_admin = db.scalar(
            select(User).where(User.role == "ADMIN", User.is_active.is_(True)).limit(1)
        )
        if existing_admin is not None:
            return
        if db.scalar(select(User).where(User.username == config.DEFAULT_ADMIN_USERNAME)) is not None:
            # 같은 아이디가 일반 계정으로 남아 있으면 건드리지 않는다.
            return
        db.add(
            User(
                username=config.DEFAULT_ADMIN_USERNAME,
                name="시스템 관리자",
                role="ADMIN",
                password_hash=hash_password(config.DEFAULT_ADMIN_PASSWORD),
            )
        )
        db.commit()
        print(
            "[초기설정] 기본 관리자 계정을 만들었습니다: "
            f"{config.DEFAULT_ADMIN_USERNAME} / {config.DEFAULT_ADMIN_PASSWORD}\n"
            "          로그인 후 반드시 비밀번호를 변경하세요."
        )


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    ensure_default_admin()
    yield


def create_app() -> FastAPI:
    app = FastAPI(
        title="IT 자산관리 시스템",
        description="사내 IT 자산의 등록·지급·반납을 관리합니다.",
        version="1.0.0",
        lifespan=lifespan,
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )

    # 미들웨어는 나중에 등록한 것이 바깥쪽에서 먼저 실행된다.
    # 아래 attach_current_user 가 request.session 을 읽으려면
    # SessionMiddleware 가 더 바깥에 있어야 하므로 순서를 바꾸면 안 된다.
    @app.middleware("http")
    async def attach_current_user(request: Request, call_next):
        """템플릿에서 쓸 수 있도록 로그인 사용자를 request.state 에 담아 둔다."""
        request.state.user = None
        user_id = request.session.get(SESSION_USER_KEY) if "session" in request.scope else None
        if user_id:
            with SessionLocal() as db:
                user = db.get(User, user_id)
                if user is not None and user.is_active:
                    request.state.user = user
        return await call_next(request)

    app.add_middleware(
        SessionMiddleware,
        secret_key=config.SECRET_KEY,
        max_age=config.SESSION_MAX_AGE,
        same_site="lax",
        https_only=False,  # 사내 HTTP 환경을 고려한 기본값. HTTPS 라면 True 권장.
    )

    app.mount("/static", StaticFiles(directory=str(config.BASE_DIR / "static")), name="static")

    app.include_router(auth.router)
    app.include_router(dashboard.router)
    app.include_router(assets.router)
    app.include_router(employees.router)
    app.include_router(assignments.router)
    app.include_router(users.router)

    @app.exception_handler(LoginRequired)
    async def on_login_required(request: Request, exc: LoginRequired):
        return login_redirect(exc.next_url)

    @app.exception_handler(HTTPException)
    async def on_http_exception(request: Request, exc: HTTPException):
        # 화면 요청이면 사람이 읽을 수 있는 오류 페이지를 보여준다.
        if exc.status_code in (status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND):
            accepts_html = "text/html" in request.headers.get("accept", "")
            if accepts_html:
                title = "접근 권한이 없습니다" if exc.status_code == 403 else "페이지를 찾을 수 없습니다"
                return render(
                    request,
                    "error.html",
                    {"code": exc.status_code, "title": title, "message": exc.detail},
                    status_code=exc.status_code,
                )
        return await http_exception_handler(request, exc)

    return app


app = create_app()
