"""자산관리 데이터 모델."""

from __future__ import annotations

from datetime import date, datetime, timezone

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Integer, Numeric, String, Text
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

# 감가상각 방법
DEPRECIATION_METHODS: dict[str, str] = {
    "NONE": "사용 안 함",
    "STRAIGHT_LINE": "정액법",
    "DECLINING": "정률법",
}

# 분류별로 흔히 쓰는 내용연수(년). 자산 등록 시 기본값을 제안하는 데 쓴다.
DEFAULT_USEFUL_LIFE: dict[str, int] = {
    "NOTEBOOK": 4,
    "DESKTOP": 5,
    "MONITOR": 5,
    "SERVER": 5,
    "NETWORK": 5,
    "MOBILE": 3,
    "PERIPHERAL": 5,
    "SOFTWARE": 1,
    "ETC": 5,
}

# 정비 이력의 종류
MAINTENANCE_KINDS: dict[str, str] = {
    "REPAIR": "수리",
    "INSPECT": "점검",
    "REPLACE": "부품 교체",
    "UPGRADE": "업그레이드",
    "ETC": "기타",
}

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

    # 2단계 인증. 계정마다 켜고 끌 수 있다.
    totp_secret: Mapped[str | None] = mapped_column(String(64))
    totp_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    # 폰을 잃어버렸을 때 쓰는 일회용 복구 코드 (해시해서 보관)
    recovery_codes: Mapped[str | None] = mapped_column(Text)

    # 무차별 대입을 막기 위한 로그인 실패 기록
    failed_logins: Mapped[int] = mapped_column(Integer, default=0)
    locked_until: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    @property
    def is_admin(self) -> bool:
        return self.role == "ADMIN"

    @property
    def role_label(self) -> str:
        return ROLES.get(self.role, self.role)

    def is_locked(self, now: datetime | None = None) -> bool:
        """로그인 실패가 쌓여 잠긴 상태인지."""
        if self.locked_until is None:
            return False
        now = now or utcnow()
        # DB 에서 읽어온 값에는 시간대 정보가 없을 수 있어 맞춰 준다
        until = self.locked_until
        if until.tzinfo is None:
            until = until.replace(tzinfo=timezone.utc)
        return until > now

    def lock_seconds_left(self, now: datetime | None = None) -> int:
        if not self.is_locked(now):
            return 0
        until = self.locked_until
        if until.tzinfo is None:
            until = until.replace(tzinfo=timezone.utc)
        return max(0, int((until - (now or utcnow())).total_seconds()))


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

    # 감가상각. 방법을 지정하지 않으면 계산하지 않는다.
    depreciation_method: Mapped[str | None] = mapped_column(String(20))
    useful_life_years: Mapped[int | None] = mapped_column(Integer)
    salvage_value: Mapped[float | None] = mapped_column(Numeric(14, 2))

    holder_id: Mapped[int | None] = mapped_column(
        ForeignKey("employees.id", ondelete="SET NULL"), nullable=True, index=True
    )
    holder: Mapped[Employee | None] = relationship(back_populates="assets")

    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)

    assignments: Mapped[list["Assignment"]] = relationship(
        back_populates="asset", cascade="all, delete-orphan", passive_deletes=True
    )
    maintenances: Mapped[list["Maintenance"]] = relationship(
        back_populates="asset",
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="Maintenance.maintained_at.desc()",
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

    # --- 감가상각 -------------------------------------------------------------

    @property
    def depreciation_label(self) -> str:
        return DEPRECIATION_METHODS.get(self.depreciation_method or "NONE", "사용 안 함")

    @property
    def depreciates(self) -> bool:
        """감가상각을 계산할 수 있는 상태인지."""
        return bool(
            self.depreciation_method
            and self.depreciation_method != "NONE"
            and self.purchase_price
            and self.purchase_date
            and self.useful_life_years
            and self.useful_life_years > 0
        )

    def months_in_service(self, today: date | None = None) -> int:
        """도입일로부터 지난 개월 수 (0 이상)."""
        if self.purchase_date is None:
            return 0
        today = today or date.today()
        months = (today.year - self.purchase_date.year) * 12 + (
            today.month - self.purchase_date.month
        )
        if today.day < self.purchase_date.day:
            months -= 1
        return max(0, months)

    def book_value(self, today: date | None = None) -> float | None:
        """현재 장부가액. 감가상각 설정이 없으면 None.

        계산은 월 단위로 한다. 연 단위로 하면 연중에 산 자산의 첫 해 상각이
        실제보다 크게 잡힌다.
        """
        if not self.depreciates:
            return None

        cost = float(self.purchase_price)
        salvage = float(self.salvage_value or 0)
        if salvage > cost:
            salvage = cost

        total_months = self.useful_life_years * 12
        used_months = min(self.months_in_service(today), total_months)

        if self.depreciation_method == "STRAIGHT_LINE":
            value = cost - (cost - salvage) * (used_months / total_months)
        else:  # 정률법 - 매년 남은 장부가액의 일정 비율을 상각한다
            # 정액법의 두 배 비율을 쓰는 정률법(이중체감법)
            monthly_rate = 2.0 / total_months
            value = cost * ((1 - monthly_rate) ** used_months)
            value = max(value, salvage)

        return round(max(value, salvage), 2)

    def accumulated_depreciation(self, today: date | None = None) -> float | None:
        """지금까지 상각된 누계액."""
        value = self.book_value(today)
        if value is None:
            return None
        return round(float(self.purchase_price) - value, 2)

    def depreciation_progress(self, today: date | None = None) -> int | None:
        """내용연수 대비 경과 비율(%). 화면의 막대 표시에 쓴다."""
        if not self.depreciates:
            return None
        total_months = self.useful_life_years * 12
        used = min(self.months_in_service(today), total_months)
        return int(round(used / total_months * 100))

    @property
    def maintenance_total_cost(self) -> float:
        """지금까지 들어간 정비 비용 합계."""
        return float(sum(float(item.cost or 0) for item in self.maintenances))


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


class Maintenance(Base):
    """자산 정비(수리·점검) 이력 한 건."""

    __tablename__ = "maintenances"

    id: Mapped[int] = mapped_column(primary_key=True)
    asset_id: Mapped[int] = mapped_column(
        ForeignKey("assets.id", ondelete="CASCADE"), index=True
    )

    maintained_at: Mapped[date] = mapped_column(Date, default=date.today, index=True)
    kind: Mapped[str] = mapped_column(String(20), default="REPAIR")
    vendor: Mapped[str | None] = mapped_column(String(80))
    description: Mapped[str] = mapped_column(Text)
    cost: Mapped[float | None] = mapped_column(Numeric(14, 2))
    next_due: Mapped[date | None] = mapped_column(Date, index=True)

    created_by: Mapped[str | None] = mapped_column(String(50))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    asset: Mapped[Asset] = relationship(back_populates="maintenances")

    @property
    def kind_label(self) -> str:
        return MAINTENANCE_KINDS.get(self.kind, self.kind)

    def days_until_due(self, today: date | None = None) -> int | None:
        """다음 점검까지 남은 일수. 예정일이 없으면 None."""
        if self.next_due is None:
            return None
        return (self.next_due - (today or date.today())).days


class Setting(Base):
    """화면에서 바꿀 수 있는 설정값 (키-값 한 쌍)."""

    __tablename__ = "settings"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[str | None] = mapped_column(Text)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow, onupdate=utcnow
    )
