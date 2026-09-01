"""자산관리 데이터 모델."""

from __future__ import annotations

from datetime import date, datetime, timezone

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


# --- 코드 값 정의 -------------------------------------------------------------
# 값은 DB 에 저장되는 코드, 라벨은 화면에 보이는 한글 이름이다.

ROLES: dict[str, str] = {
    "ADMIN": "관리자",
    "USER": "일반 사용자",
}

ASSET_CATEGORIES: dict[str, str] = {
    "NOTEBOOK": "노트북",
    "DESKTOP": "데스크톱",
    "MONITOR": "모니터",
    "SERVER": "서버",
    "NETWORK": "네트워크 장비",
    "MOBILE": "모바일 기기",
    "PERIPHERAL": "주변기기",
    "SOFTWARE": "소프트웨어",
    "ETC": "기타",
}

ASSET_STATUSES: dict[str, str] = {
    "IN_STOCK": "재고",
    "IN_USE": "사용중",
    "REPAIR": "수리중",
    "LOST": "분실",
    "DISPOSED": "폐기",
}

# 지급이 가능한 상태 (이미 사용중이거나 폐기/분실된 자산은 지급할 수 없다)
ASSIGNABLE_STATUSES = ("IN_STOCK", "REPAIR")

# 반납 처리 시 선택할 수 있는 자산 상태
RETURN_STATUSES = ("IN_STOCK", "REPAIR", "LOST", "DISPOSED")

EMPLOYEE_STATUSES: dict[str, str] = {
    "ACTIVE": "재직",
    "LEAVE": "휴직",
    "RESIGNED": "퇴사",
}


class User(Base):
    """시스템 로그인 계정."""

    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    name: Mapped[str] = mapped_column(String(50))
    role: Mapped[str] = mapped_column(String(20), default="USER")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    @property
    def is_admin(self) -> bool:
        return self.role == "ADMIN"

    @property
    def role_label(self) -> str:
        return ROLES.get(self.role, self.role)


class Employee(Base):
    """자산을 지급받는 임직원."""

    __tablename__ = "employees"

    id: Mapped[int] = mapped_column(primary_key=True)
    emp_no: Mapped[str] = mapped_column(String(30), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(50), index=True)
    department: Mapped[str | None] = mapped_column(String(50), index=True)
    position: Mapped[str | None] = mapped_column(String(50))
    email: Mapped[str | None] = mapped_column(String(120))
    phone: Mapped[str | None] = mapped_column(String(30))
    status: Mapped[str] = mapped_column(String(20), default="ACTIVE")
    note: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    assets: Mapped[list["Asset"]] = relationship(back_populates="holder")
    assignments: Mapped[list["Assignment"]] = relationship(back_populates="employee")

    @property
    def status_label(self) -> str:
        return EMPLOYEE_STATUSES.get(self.status, self.status)

    @property
    def display_name(self) -> str:
        parts = [self.name]
        if self.department:
            parts.append(f"({self.department})")
        return " ".join(parts)


class Asset(Base):
    """관리 대상 IT 자산 한 건."""

    __tablename__ = "assets"

    id: Mapped[int] = mapped_column(primary_key=True)
    asset_no: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120), index=True)
    category: Mapped[str] = mapped_column(String(30), default="ETC", index=True)
    status: Mapped[str] = mapped_column(String(20), default="IN_STOCK", index=True)

    manufacturer: Mapped[str | None] = mapped_column(String(60))
    model_name: Mapped[str | None] = mapped_column(String(120))
    serial_no: Mapped[str | None] = mapped_column(String(120), index=True)
    spec: Mapped[str | None] = mapped_column(Text)

    location: Mapped[str | None] = mapped_column(String(80))
    supplier: Mapped[str | None] = mapped_column(String(80))
    purchase_date: Mapped[date | None] = mapped_column(Date)
    purchase_price: Mapped[float | None] = mapped_column(Numeric(14, 2))
    warranty_until: Mapped[date | None] = mapped_column(Date)
    license_key: Mapped[str | None] = mapped_column(String(255))
    note: Mapped[str | None] = mapped_column(Text)

    holder_id: Mapped[int | None] = mapped_column(
        ForeignKey("employees.id", ondelete="SET NULL"), nullable=True, index=True
    )
    holder: Mapped[Employee | None] = relationship(back_populates="assets")

    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)

    assignments: Mapped[list["Assignment"]] = relationship(
        back_populates="asset", cascade="all, delete-orphan", passive_deletes=True
    )

    @property
    def category_label(self) -> str:
        return ASSET_CATEGORIES.get(self.category, self.category)

    @property
    def status_label(self) -> str:
        return ASSET_STATUSES.get(self.status, self.status)

    @property
    def is_assigned(self) -> bool:
        return self.holder_id is not None

    def warranty_days_left(self, today: date | None = None) -> int | None:
        """보증 만료까지 남은 일수. 보증일이 없으면 None."""
        if self.warranty_until is None:
            return None
        return (self.warranty_until - (today or date.today())).days


class Assignment(Base):
    """자산 지급/반납 이력 한 건.

    returned_at 이 비어 있으면 현재 지급 중인 건이다.
    """

    __tablename__ = "assignments"

    id: Mapped[int] = mapped_column(primary_key=True)
    asset_id: Mapped[int] = mapped_column(
        ForeignKey("assets.id", ondelete="CASCADE"), index=True
    )
    employee_id: Mapped[int] = mapped_column(
        ForeignKey("employees.id", ondelete="RESTRICT"), index=True
    )

    assigned_at: Mapped[date] = mapped_column(Date, default=date.today)
    assigned_note: Mapped[str | None] = mapped_column(Text)
    returned_at: Mapped[date | None] = mapped_column(Date, nullable=True, index=True)
    return_note: Mapped[str | None] = mapped_column(Text)

    created_by: Mapped[str | None] = mapped_column(String(50))
    returned_by: Mapped[str | None] = mapped_column(String(50))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    asset: Mapped[Asset] = relationship(back_populates="assignments")
    employee: Mapped[Employee] = relationship(back_populates="assignments")

    @property
    def is_open(self) -> bool:
        """아직 반납되지 않은 지급 건인지."""
        return self.returned_at is None

    @property
    def days_held(self) -> int:
        """보유 일수 (반납했으면 지급일~반납일, 아니면 지급일~오늘)."""
        end = self.returned_at or date.today()
        return (end - self.assigned_at).days
