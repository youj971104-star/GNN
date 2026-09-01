"""데이터베이스 백업 테스트."""

import sqlite3
from pathlib import Path

import pytest

from app import backup as backup_module
from app.models import Asset, Employee


def test_백업_파일에_자산_데이터가_그대로_담긴다(db, tmp_path):
    db.add_all(
        [
            Asset(asset_no="IT-0001", name="백업 대상 노트북", category="NOTEBOOK"),
            Asset(asset_no="IT-0002", name="백업 대상 모니터", category="MONITOR"),
        ]
    )
    db.add(Employee(emp_no="E001", name="홍길동", department="개발팀"))
    db.commit()

    destination = backup_module.backup(tmp_path / "backup.db")

    assert destination.exists()
    with destination.open("rb") as handle:
        assert handle.read(15) == b"SQLite format 3"

    copy = sqlite3.connect(destination)
    assert copy.execute("SELECT COUNT(*) FROM assets").fetchone()[0] == 2
    assert copy.execute("SELECT COUNT(*) FROM employees").fetchone()[0] == 1
    names = {row[0] for row in copy.execute("SELECT name FROM assets")}
    assert names == {"백업 대상 노트북", "백업 대상 모니터"}
    copy.close()


def test_백업은_원본을_바꾸지_않는다(db, asset, tmp_path):
    backup_module.backup(tmp_path / "backup.db")

    db.expire_all()
    assert db.query(Asset).count() == 1


def test_저장_폴더가_없으면_만들어_준다(db, asset, tmp_path):
    destination = backup_module.backup(tmp_path / "없는폴더" / "하위" / "backup.db")
    assert destination.exists()


def test_백업_파일로_다시_열어도_동작한다(db, asset, tmp_path):
    """복원 후 서비스가 정상적으로 읽고 쓸 수 있는 상태여야 한다."""
    destination = backup_module.backup(tmp_path / "backup.db")

    restored = sqlite3.connect(destination)
    restored.execute(
        "INSERT INTO assets (asset_no, name, category, status, created_at, updated_at)"
        " VALUES (?,?,?,?, datetime('now'), datetime('now'))",
        ("IT-NEW", "복원 후 추가", "ETC", "IN_STOCK"),
    )
    restored.commit()
    assert restored.execute("SELECT COUNT(*) FROM assets").fetchone()[0] == 2
    restored.close()


def test_DB_파일이_없으면_안내_메시지를_준다(tmp_path, monkeypatch):
    monkeypatch.setattr(backup_module, "sqlite_path", lambda: tmp_path / "없는파일.db")

    with pytest.raises(SystemExit, match="찾을 수 없습니다"):
        backup_module.backup(tmp_path / "backup.db")


def test_SQLite_가_아니면_다른_백업_도구를_안내한다(monkeypatch):
    monkeypatch.setattr(
        backup_module.config, "DATABASE_URL", "postgresql+psycopg://user@host/itam"
    )

    with pytest.raises(SystemExit, match="pg_dump"):
        backup_module.sqlite_path()


def test_명령행_인자가_없으면_사용법을_알려준다():
    assert backup_module.main(["app.backup"]) == 2


def test_명령행으로_백업할_수_있다(db, asset, tmp_path, capsys):
    target = tmp_path / "cli-backup.db"
    assert backup_module.main(["app.backup", str(target)]) == 0

    assert target.exists()
    assert "백업 완료" in capsys.readouterr().out


def test_설정된_DB_경로를_읽는다():
    path = backup_module.sqlite_path()
    assert isinstance(path, Path)
    assert path.name.endswith(".db")
