"""데이터베이스 백업 - 서비스를 멈추지 않고 안전하게 스냅샷을 뜬다.

    python -m app.backup /backups/itam-20260901.db

SQLite 의 온라인 백업 API 를 쓰므로, 백업 중에 다른 사용자가 자산을 등록하거나
수정해도 일관된 시점의 파일이 만들어진다. (파일을 그냥 cp 하면 쓰기 도중의
어중간한 상태가 복사될 수 있다.)
"""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

from app import config

SQLITE_PREFIX = "sqlite:///"


def sqlite_path() -> Path:
    """설정된 DATABASE_URL 에서 SQLite 파일 경로를 꺼낸다."""
    url = config.DATABASE_URL
    if not url.startswith(SQLITE_PREFIX):
        raise SystemExit(
            "이 스크립트는 SQLite 전용입니다. 현재 설정은 다른 데이터베이스를 쓰고 있어\n"
            "해당 DBMS 의 백업 도구(예: pg_dump)를 사용해야 합니다."
        )
    # sqlite:////data/itam.db 처럼 슬래시가 네 개면 절대경로다.
    return Path("/" + url[len(SQLITE_PREFIX):].lstrip("/"))


def backup(destination: Path) -> Path:
    source = sqlite_path()
    if not source.exists():
        raise SystemExit(f"데이터베이스 파일을 찾을 수 없습니다: {source}")

    destination.parent.mkdir(parents=True, exist_ok=True)

    with sqlite3.connect(f"file:{source}?mode=ro", uri=True) as src, \
            sqlite3.connect(destination) as dst:
        src.backup(dst)

    return destination


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("사용법: python -m app.backup <저장할_파일_경로>", file=sys.stderr)
        return 2

    path = backup(Path(argv[1]))
    size_mb = path.stat().st_size / (1024 * 1024)
    print(f"백업 완료: {path} ({size_mb:.2f} MB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
