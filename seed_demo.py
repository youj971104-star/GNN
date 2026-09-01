#!/usr/bin/env python3
"""데모/교육용 샘플 데이터를 넣는 스크립트.

    python seed_demo.py

실제 운영 DB 에는 실행하지 마세요. 이미 자산이 등록되어 있으면 아무 것도 하지 않습니다.
"""

from datetime import date, timedelta

from sqlalchemy import select

from app.database import SessionLocal, init_db
from app.models import Asset, Assignment, Employee, User
from app.security import hash_password

EMPLOYEES = [
    ("2021001", "김서준", "개발팀", "팀장", "seojun.kim@example.com", "010-1234-0001"),
    ("2021002", "이하윤", "개발팀", "선임", "hayun.lee@example.com", "010-1234-0002"),
    ("2022003", "박도윤", "디자인팀", "주임", "doyun.park@example.com", "010-1234-0003"),
    ("2022004", "최지우", "영업팀", "과장", "jiwoo.choi@example.com", "010-1234-0004"),
    ("2023005", "정민서", "경영지원팀", "대리", "minseo.jung@example.com", "010-1234-0005"),
    ("2023006", "강수아", "IT운영팀", "선임", "sua.kang@example.com", "010-1234-0006"),
]

ASSETS = [
    ("IT-2024-0001", "개발팀 노트북", "NOTEBOOK", "LG전자", "그램 16 (2024)", "SN-GR16-2401", "i7 / 32GB / 1TB", 2_150_000, "2024-03-04", "2027-03-03"),
    ("IT-2024-0002", "개발팀 노트북", "NOTEBOOK", "Apple", "MacBook Pro 14", "SN-MBP14-2402", "M3 Pro / 36GB / 1TB", 3_290_000, "2024-03-04", "2027-03-03"),
    ("IT-2024-0003", "디자인팀 데스크톱", "DESKTOP", "삼성전자", "DB400T", "SN-DB400-2403", "i7 / 32GB / 1TB", 1_480_000, "2024-05-20", "2027-05-19"),
    ("IT-2024-0004", "27인치 모니터", "MONITOR", "LG전자", "27UP850", "SN-27UP-2404", "4K / IPS", 520_000, "2024-05-20", "2026-11-19"),
    ("IT-2024-0005", "27인치 모니터", "MONITOR", "LG전자", "27UP850", "SN-27UP-2405", "4K / IPS", 520_000, "2024-05-20", "2026-11-19"),
    ("IT-2025-0006", "영업팀 노트북", "NOTEBOOK", "삼성전자", "갤럭시북4 Pro", "SN-GB4P-2506", "Ultra7 / 16GB / 512GB", 1_890_000, "2025-02-11", "2028-02-10"),
    ("IT-2025-0007", "업무용 휴대폰", "MOBILE", "삼성전자", "갤럭시 S24", "SN-S24-2507", "256GB", 1_155_000, "2025-04-02", "2027-04-01"),
    ("IT-2025-0008", "사내 파일서버", "SERVER", "Dell", "PowerEdge R650", "SN-R650-2508", "Xeon Silver / 64GB / 8TB", 8_400_000, "2025-06-18", "2028-06-17"),
    ("IT-2025-0009", "사무실 스위치", "NETWORK", "Cisco", "CBS350-24T", "SN-CBS350-2509", "24포트 기가비트", 780_000, "2025-06-18", "2028-06-17"),
    ("IT-2025-0010", "Adobe Creative Cloud", "SOFTWARE", "Adobe", "CC 그룹판", None, "1 사용자 / 연간", 780_000, "2025-08-01", "2026-07-31"),
    ("IT-2025-0011", "MS Office 365", "SOFTWARE", "Microsoft", "Business Standard", None, "5 사용자 / 연간", 1_050_000, "2025-08-01", "2026-07-31"),
    ("IT-2026-0012", "회의실 프로젝터", "PERIPHERAL", "Epson", "EB-L200SW", "SN-EBL200-2612", "단초점 / 3800안시", 1_320_000, "2026-01-09", "2029-01-08"),
    ("IT-2026-0013", "예비용 노트북", "NOTEBOOK", "LG전자", "그램 15", "SN-GR15-2613", "i5 / 16GB / 512GB", 1_450_000, "2026-01-09", "2029-01-08"),
    ("IT-2026-0014", "USB-C 도킹스테이션", "PERIPHERAL", "Dell", "WD19S", "SN-WD19-2614", "130W", 290_000, "2026-02-02", "2028-02-01"),
    ("IT-2026-0015", "무선 프린터", "PERIPHERAL", "HP", "M283fdw", "SN-M283-2615", "컬러 레이저 복합기", 640_000, "2026-02-02", "2028-02-01"),
]

# (자산번호, 사번, 지급일, 반납일)
ASSIGNMENTS = [
    ("IT-2024-0001", "2021001", "2024-03-05", None),
    ("IT-2024-0002", "2021002", "2024-03-05", None),
    ("IT-2024-0003", "2022003", "2024-05-21", None),
    ("IT-2024-0004", "2022003", "2024-05-21", None),
    ("IT-2025-0006", "2022004", "2025-02-12", None),
    ("IT-2025-0007", "2022004", "2025-04-03", None),
    ("IT-2026-0014", "2021001", "2026-02-03", None),
    # 반납이 끝난 이력
    ("IT-2024-0005", "2023005", "2024-06-03", "2025-12-19"),
    ("IT-2026-0013", "2023006", "2026-01-12", "2026-05-08"),
]


def main() -> None:
    init_db()
    with SessionLocal() as db:
        if db.scalar(select(Asset).limit(1)) is not None:
            print("이미 자산 데이터가 있어 샘플을 넣지 않았습니다.")
            return

        if db.scalar(select(User).where(User.username == "viewer")) is None:
            db.add(
                User(
                    username="viewer",
                    name="조회 담당자",
                    role="USER",
                    password_hash=hash_password("viewer1234"),
                )
            )

        employees: dict[str, Employee] = {}
        for emp_no, name, dept, position, email, phone in EMPLOYEES:
            emp = Employee(
                emp_no=emp_no, name=name, department=dept, position=position,
                email=email, phone=phone, status="ACTIVE",
            )
            db.add(emp)
            employees[emp_no] = emp

        assets: dict[str, Asset] = {}
        for (asset_no, name, category, maker, model, serial, spec, price, bought, warranty) in ASSETS:
            asset = Asset(
                asset_no=asset_no, name=name, category=category, status="IN_STOCK",
                manufacturer=maker, model_name=model, serial_no=serial, spec=spec,
                purchase_price=price,
                purchase_date=date.fromisoformat(bought),
                warranty_until=date.fromisoformat(warranty),
                location="본사 3층 창고",
                supplier="테크상사",
            )
            db.add(asset)
            assets[asset_no] = asset
        db.flush()

        for asset_no, emp_no, assigned, returned in ASSIGNMENTS:
            asset, employee = assets[asset_no], employees[emp_no]
            db.add(
                Assignment(
                    asset_id=asset.id,
                    employee_id=employee.id,
                    assigned_at=date.fromisoformat(assigned),
                    returned_at=date.fromisoformat(returned) if returned else None,
                    assigned_note="샘플 데이터",
                    return_note="샘플 반납" if returned else None,
                    created_by="admin",
                )
            )
            if returned is None:
                asset.status = "IN_USE"
                asset.holder_id = employee.id

        # 상태가 다양해야 대시보드가 의미 있게 보인다
        assets["IT-2026-0015"].status = "REPAIR"
        assets["IT-2024-0005"].status = "DISPOSED"
        assets["IT-2025-0010"].warranty_until = date.today() + timedelta(days=35)

        db.commit()
        print(f"샘플 데이터를 넣었습니다: 직원 {len(EMPLOYEES)}명, 자산 {len(ASSETS)}건, 이력 {len(ASSIGNMENTS)}건")
        print("조회 전용 계정: viewer / viewer1234")


if __name__ == "__main__":
    main()
