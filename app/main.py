"""애플리케이션 진입점."""

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exception_handlers import http_exception_handler
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import select, text
from starlette.middleware.sessions import SessionMiddleware

from app import config
from app.database import SessionLocal, init_db
from app.deps import LoginRequired, login_redirect, session_user_id
from app.models import User
from app.routers import (
    assets,
    assignments,
    auth,
    dashboard,
    employees,
    maintenance,
    pwa,
    scan,
    search,
    settings as settings_router,
    shortlink,
    users,
)
from app.security import hash_password
from app.templating import render


# 모든 응답에 붙이는 보안 헤더.
#
# CSP(Content-Security-Policy)는 '이 화면은 우리 서버에서 받은 스크립트만
# 실행한다'고 브라우저에 알려 준다. 값에 섞여 들어온 코드가 실행되는 사고를
# 한 겹 더 막아 준다. 그래서 화면 안에 자바스크립트를 직접 적지 않고
# 모두 /static/js 파일로 두었다.
#
# style 만 'unsafe-inline' 을 허용한다. 화면 곳곳에서 style="..." 을 쓰기
# 때문인데, 스타일은 코드 실행으로 이어지지 않는다.
SECURITY_HEADERS = {
    "Content-Security-Policy": "; ".join(
        [
            "default-src 'self'",
            "script-src 'self'",
            "style-src 'self' 'unsafe-inline'",
            "img-src 'self' data:",
            "font-src 'self'",
            "object-src 'none'",
            "base-uri 'self'",
            "frame-ancestors 'none'",   # 다른 사이트가 화면을 몰래 끼워 넣지 못하게
            "form-action 'self'",
        ]
    ),
    # 내려준 파일의 형식을 브라우저가 멋대로 추측하지 않게 한다
    "X-Content-Type-Options": "nosniff",
    # 예전 브라우저용 (CSP 의 frame-ancestors 와 같은 목적)
    "X-Frame-Options": "DENY",
    # 다른 사이트로 나갈 때 우리 주소를 넘기지 않는다
    "Referrer-Policy": "same-origin",
}

# HTTPS 로 쓰는 중이라면, 다음부터는 처음부터 HTTPS 로만 접속하도록 지시한다.
# 기간을 30일로 둔 것은, HTTP 로 되돌려야 할 때 오래 발이 묶이지 않게 하기 위해서다.
HSTS_HEADER = ("Strict-Transport-Security", "max-age=2592000")


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
        user_id = session_user_id(request)
        if user_id:
            with SessionLocal() as db:
                user = db.get(User, user_id)
                if user is not None and user.is_active:
                    request.state.user = user
        return await call_next(request)

    @app.middleware("http")
    async def add_security_headers(request: Request, call_next):
        response = await call_next(request)
        for name, value in SECURITY_HEADERS.items():
            response.headers.setdefault(name, value)
        if request.url.path.startswith("/static/") and response.status_code == 200:
            # 주소에 내용 지문(?v=)이 붙은 파일은 내용이 바뀌면 주소도 바뀌므로 오래 저장해도 된다.
            # 지문이 없는 주소는 업데이트 뒤 예전 파일이 남지 않도록 매번 바뀌었는지 확인하게 한다.
            if request.query_params.get("v"):
                response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
            else:
                response.headers["Cache-Control"] = "no-cache"
        if config.HTTPS_ONLY:
            response.headers.setdefault(*HSTS_HEADER)
        return response

    app.add_middleware(
        SessionMiddleware,
        secret_key=config.SECRET_KEY,
        max_age=config.SESSION_MAX_AGE,
        same_site="lax",
        # 사내망 HTTP 환경에서는 0, 도메인 + HTTPS 로 전환하면 ITAM_HTTPS_ONLY=1 로 바꾼다.
        https_only=config.HTTPS_ONLY,
    )

    app.mount("/static", StaticFiles(directory=str(config.BASE_DIR / "static")), name="static")

    app.include_router(auth.router)
    app.include_router(dashboard.router)
    app.include_router(assets.router)
    app.include_router(employees.router)
    app.include_router(assignments.router)
    app.include_router(maintenance.router)
    app.include_router(users.router)
    app.include_router(settings_router.router)
    app.include_router(scan.router)
    app.include_router(shortlink.router)
    app.include_router(pwa.router)
    app.include_router(search.router)

    @app.get(config.HEALTH_PATH, include_in_schema=False)
    def healthcheck():
        """컨테이너·로드밸런서가 호출하는 상태 확인. 로그인 없이 열려 있다.

        DB 까지 실제로 조회해 보므로, 응답이 200 이면 서비스가 요청을 받을 수 있는 상태다.
        """
        try:
            with SessionLocal() as db:
                db.execute(text("SELECT 1"))
        except Exception:
            return JSONResponse(
                {"status": "error", "detail": "데이터베이스에 연결할 수 없습니다."},
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        return {"status": "ok", "version": app.version}

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
