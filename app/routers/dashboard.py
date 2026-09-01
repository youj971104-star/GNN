"""대시보드(첫 화면)."""

from fastapi import APIRouter, Request

from app.deps import CurrentUser, DbSession
from app.services import dashboard_stats
from app.templating import render

router = APIRouter(tags=["대시보드"])


@router.get("/")
def dashboard(request: Request, db: DbSession, user: CurrentUser):
    return render(request, "dashboard.html", {"stats": dashboard_stats(db)})
