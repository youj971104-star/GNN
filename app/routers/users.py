"""사용자 계정 관리 (관리자 전용)."""

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import RedirectResponse
from sqlalchemy import func, select

from app import forms
from app.deps import AdminUser, DbSession
from app.models import ROLES, User
from app.security import hash_password, validate_password
from app.templating import flash, render

router = APIRouter(prefix="/users", tags=["계정"])


def _get_user(db: DbSession, user_id: int) -> User:
    target = db.get(User, user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="계정을 찾을 수 없습니다.")
    return target


def _admin_count(db: DbSession) -> int:
    return db.scalar(
        select(func.count(User.id)).where(User.role == "ADMIN", User.is_active.is_(True))
    ) or 0


@router.get("")
def list_users(request: Request, db: DbSession, user: AdminUser):
    users = list(db.scalars(select(User).order_by(User.role, User.username)).all())
    return render(request, "users/list.html", {"users": users})


@router.get("/new")
def new_user_form(request: Request, user: AdminUser):
    return render(request, "users/form.html", {"target": None, "form": {"role": "USER"}})


@router.post("/new")
async def create_user(request: Request, db: DbSession, user: AdminUser):
    data = dict(await request.form())
    try:
        username = forms.required_str(data.get("username"), "아이디", 50)
        name = forms.required_str(data.get("name"), "이름", 50)
        role = forms.parse_choice(data.get("role"), ROLES, "권한", "USER")
        password = data.get("password") or ""
        error = validate_password(password)
        if error:
            raise ValueError(error)
        if password != (data.get("confirm_password") or ""):
            raise ValueError("비밀번호와 확인 값이 서로 다릅니다.")
        if db.scalar(select(User).where(User.username == username)):
            raise ValueError(f"아이디 '{username}'는 이미 사용 중입니다.")
    except ValueError as exc:
        return render(
            request,
            "users/form.html",
            {"target": None, "form": data, "error": str(exc)},
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    account = User(username=username, name=name, role=role, password_hash=hash_password(password))
    db.add(account)
    db.commit()
    flash(request, f"계정 '{username}' 을(를) 만들었습니다.")
    return RedirectResponse("/users", status_code=status.HTTP_303_SEE_OTHER)


@router.get("/{user_id}/edit")
def edit_user_form(request: Request, db: DbSession, user: AdminUser, user_id: int):
    return render(request, "users/form.html", {"target": _get_user(db, user_id), "form": None})


@router.post("/{user_id}/edit")
async def update_user(request: Request, db: DbSession, user: AdminUser, user_id: int):
    target = _get_user(db, user_id)
    data = dict(await request.form())

    try:
        name = forms.required_str(data.get("name"), "이름", 50)
        role = forms.parse_choice(data.get("role"), ROLES, "권한", "USER")
        is_active = data.get("is_active") == "on"
        new_password = (data.get("password") or "").strip()

        # 마지막 관리자를 스스로 잠가버리는 상황을 막는다.
        losing_admin = target.role == "ADMIN" and target.is_active and (role != "ADMIN" or not is_active)
        if losing_admin and _admin_count(db) <= 1:
            raise ValueError("활성화된 관리자 계정이 최소 1개는 있어야 합니다.")
        if target.id == user.id and not is_active:
            raise ValueError("본인 계정은 비활성화할 수 없습니다.")

        if new_password:
            error = validate_password(new_password)
            if error:
                raise ValueError(error)
            if new_password != (data.get("confirm_password") or ""):
                raise ValueError("비밀번호와 확인 값이 서로 다릅니다.")
    except ValueError as exc:
        return render(
            request,
            "users/form.html",
            {"target": target, "form": data, "error": str(exc)},
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    target.name = name
    target.role = role
    target.is_active = is_active
    if new_password:
        target.password_hash = hash_password(new_password)
    db.commit()
    flash(request, f"계정 '{target.username}' 정보를 수정했습니다.")
    return RedirectResponse("/users", status_code=status.HTTP_303_SEE_OTHER)


@router.post("/{user_id}/delete")
def delete_user(request: Request, db: DbSession, user: AdminUser, user_id: int):
    target = _get_user(db, user_id)
    if target.id == user.id:
        flash(request, "본인 계정은 삭제할 수 없습니다.", "error")
        return RedirectResponse("/users", status_code=status.HTTP_303_SEE_OTHER)
    if target.role == "ADMIN" and target.is_active and _admin_count(db) <= 1:
        flash(request, "활성화된 관리자 계정이 최소 1개는 있어야 합니다.", "error")
        return RedirectResponse("/users", status_code=status.HTTP_303_SEE_OTHER)

    username = target.username
    db.delete(target)
    db.commit()
    flash(request, f"계정 '{username}' 을(를) 삭제했습니다.")
    return RedirectResponse("/users", status_code=status.HTTP_303_SEE_OTHER)
