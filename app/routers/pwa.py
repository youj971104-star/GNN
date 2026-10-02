"""폰 홈 화면에 앱처럼 설치하기 (PWA).

브라우저가 '이 사이트는 앱으로 설치할 수 있다'고 판단하려면 세 가지가 필요하다.

1. HTTPS 주소
2. 앱 정보 파일(/manifest.webmanifest) - 이름, 아이콘, 처음 열 화면, 주소창 없이 열기
3. 서비스 워커(/sw.js) - 인터넷이 끊겼을 때 하얀 화면 대신 안내 화면을 보여 준다

설치해도 화면과 데이터는 지금 서버 그대로다. 서버를 업데이트하면 폰의 앱도
다음에 열 때 바로 바뀐다. 앱 스토어나 심사는 필요 없다.
"""

from fastapi import APIRouter, Request
from fastapi.responses import FileResponse, JSONResponse

from app import config
from app.deps import CurrentUser
from app.templating import render, templates

router = APIRouter(tags=["앱 설치"])

SERVICE_WORKER = config.BASE_DIR / "static" / "js" / "sw.js"

# 상단 막대(상태 표시줄) 색. 사이드바와 같은 남색이다.
THEME_COLOR = "#1f3b63"


@router.get("/manifest.webmanifest", include_in_schema=False)
def manifest():
    name = templates.env.globals["APP_NAME"]
    return JSONResponse(
        {
            "id": "/",
            "name": name,
            "short_name": "자산관리",
            "description": "사내 IT 자산의 등록·지급·반납과 QR 스캔",
            "lang": "ko",
            "start_url": "/",
            "scope": "/",
            "display": "standalone",
            "orientation": "any",
            "background_color": "#f4f6fa",
            "theme_color": THEME_COLOR,
            "icons": [
                {"src": "/static/icons/icon-192.png", "sizes": "192x192", "type": "image/png"},
                {"src": "/static/icons/icon-512.png", "sizes": "512x512", "type": "image/png"},
                {
                    "src": "/static/icons/maskable-512.png",
                    "sizes": "512x512",
                    "type": "image/png",
                    "purpose": "maskable",
                },
            ],
            # 앱 아이콘을 길게 누르면 나오는 바로가기
            "shortcuts": [
                {"name": "QR 스캔", "url": "/scan",
                 "icons": [{"src": "/static/icons/icon-192.png", "sizes": "192x192"}]},
                {"name": "자산 관리", "url": "/assets",
                 "icons": [{"src": "/static/icons/icon-192.png", "sizes": "192x192"}]},
            ],
        },
        media_type="application/manifest+json",
    )


@router.get("/sw.js", include_in_schema=False)
def service_worker():
    """서비스 워커는 사이트 전체(/)를 맡아야 해서 /static 이 아니라 맨 위 주소에서 내려준다.

    no-cache 로 두어, 서버를 업데이트하면 폰이 새 서비스 워커를 바로 받게 한다.
    """
    return FileResponse(
        SERVICE_WORKER,
        media_type="text/javascript",
        headers={"Cache-Control": "no-cache", "Service-Worker-Allowed": "/"},
    )


@router.get("/offline", include_in_schema=False)
def offline(request: Request):
    """인터넷이 끊겼을 때 보여 줄 화면. 설치할 때 미리 받아 둔다(로그인 불필요).

    서비스 워커가 뒤에서 몰래 받아 가는 화면이라 render() 를 쓰지 않는다.
    render() 는 '다음 화면에 한 번 보여 줄 안내'를 꺼내 쓰므로, 로그인 직후의
    안내 문구를 이 화면이 대신 가져가 버린다.
    """
    return templates.TemplateResponse(request, "offline.html", {"request": request})


@router.get("/install")
def install_guide(request: Request, user: CurrentUser):
    return render(request, "install.html")
