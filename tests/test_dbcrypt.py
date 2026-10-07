"""데이터베이스 파일 암호화 (SQLCipher)."""

import sqlite3

import pytest

pytest.importorskip("sqlcipher3", reason="암호화 드라이버는 리눅스 x86_64 에서만 설치된다")

from sqlalchemy import text  # noqa: E402
from sqlalchemy.orm import Session  # noqa: E402

from app import backup, config, dbcrypt  # noqa: E402
from app.database import Base, build_engine  # noqa: E402
from app.models import Asset, Employee  # noqa: E402

KEY = dbcrypt.new_key()


def _make_db(path, *, key=None, assets=5):
    """앱과 같은 구조의 DB 를 만들고 자산 몇 건을 넣는다."""
    engine = build_engine(f"sqlite:///{path}", key=key)
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        db.add_all([Asset(asset_no=f"{i:04d}", name=f"노트북 {i}") for i in range(1, assets + 1)])
        db.add(Employee(emp_no="E0001", name="홍길동"))
        db.commit()
    engine.dispose()
    return path


# --- 키 -----------------------------------------------------------------------

def test_새_키는_64자리_16진수():
    key = dbcrypt.new_key()
    assert len(key) == 64
    int(key, 16)
    assert dbcrypt.new_key() != key


@pytest.mark.parametrize("bad", [None, "", "abc", "g" * 64, KEY + "00"])
def test_형식이_틀린_키는_거부한다(bad):
    with pytest.raises(dbcrypt.DatabaseKeyError):
        dbcrypt.validate_key(bad)


# --- 암호화된 DB 로 앱을 쓴다 -------------------------------------------------------

def test_키가_있으면_파일이_암호화되어_저장된다(tmp_path):
    path = _make_db(tmp_path / "itam.db", key=KEY)

    assert not dbcrypt.is_plaintext(path)
    # 파일 안을 들여다봐도 자산 이름이 보이지 않는다
    assert "노트북".encode() not in path.read_bytes()


def test_키가_없으면_열리지_않는다(tmp_path):
    path = _make_db(tmp_path / "itam.db", key=KEY)

    with pytest.raises(sqlite3.DatabaseError):
        sqlite3.connect(path).execute("SELECT * FROM assets").fetchall()


def test_틀린_키로도_열리지_않는다(tmp_path):
    path = _make_db(tmp_path / "itam.db", key=KEY)

    with pytest.raises(dbcrypt.DatabaseKeyError):
        dbcrypt.connect(path, dbcrypt.new_key())


def test_같은_키로는_그대로_읽고_쓴다(tmp_path):
    path = _make_db(tmp_path / "itam.db", key=KEY, assets=3)

    engine = build_engine(f"sqlite:///{path}", key=KEY)
    with Session(engine) as db:
        db.add(Asset(asset_no="0004", name="새로 등록"))
        db.commit()
        assert db.query(Asset).count() == 4
        # 외래키·WAL 설정도 암호화와 함께 그대로 켜진다
        assert db.execute(text("PRAGMA foreign_keys")).scalar() == 1
        assert db.execute(text("PRAGMA journal_mode")).scalar() == "wal"
    engine.dispose()


# --- 평문 → 암호화 변환 -------------------------------------------------------------

def test_지금_쓰던_평문_DB_를_암호화한다(tmp_path):
    plain = _make_db(tmp_path / "plain.db", assets=118)
    encrypted = tmp_path / "encrypted.db"

    counts = dbcrypt.encrypt_file(plain, encrypted, KEY)

    assert counts["assets"] == 118
    assert counts["employees"] == 1
    assert not dbcrypt.is_plaintext(encrypted)
    assert dbcrypt.is_plaintext(plain)          # 원본은 건드리지 않는다

    # 앱이 그대로 열어 쓸 수 있다
    engine = build_engine(f"sqlite:///{encrypted}", key=KEY)
    with Session(engine) as db:
        assert db.query(Asset).filter_by(asset_no="0118").one().name == "노트북 118"
    engine.dispose()


def test_WAL_에만_있던_최신_내용도_함께_옮긴다(tmp_path):
    """서비스를 멈춘 직후엔 마지막 변경이 아직 WAL 파일에만 있을 수 있다."""
    plain = tmp_path / "plain.db"
    conn = sqlite3.connect(plain)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA wal_autocheckpoint=0")      # 본 파일로 옮기지 않고 WAL 에 둔다
    conn.execute("CREATE TABLE t (v TEXT)")
    conn.execute("INSERT INTO t VALUES ('WAL 에만 있는 값')")
    conn.commit()
    assert (tmp_path / "plain.db-wal").stat().st_size > 0

    encrypted = tmp_path / "enc.db"
    dbcrypt.encrypt_file(plain, encrypted, KEY)
    conn.close()

    check = dbcrypt.connect(encrypted, KEY)
    assert check.execute("SELECT v FROM t").fetchone()[0] == "WAL 에만 있는 값"
    check.close()


def test_이미_암호화된_파일은_다시_암호화하지_않는다(tmp_path):
    path = _make_db(tmp_path / "itam.db", key=KEY)
    with pytest.raises(dbcrypt.DatabaseKeyError):
        dbcrypt.encrypt_file(path, tmp_path / "again.db", KEY)


def test_다른_곳으로_옮길_때는_평문으로_되돌릴_수_있다(tmp_path):
    encrypted = _make_db(tmp_path / "enc.db", key=KEY, assets=7)
    plain = tmp_path / "plain.db"

    counts = dbcrypt.decrypt_file(encrypted, plain, KEY)

    assert counts["assets"] == 7
    assert dbcrypt.is_plaintext(plain)
    assert sqlite3.connect(plain).execute("SELECT count(*) FROM assets").fetchone()[0] == 7


# --- 서비스 시작 전 점검 --------------------------------------------------------------

def test_키를_넣었는데_파일이_평문이면_변환하라고_알려준다(tmp_path):
    plain = _make_db(tmp_path / "itam.db")
    with pytest.raises(dbcrypt.DatabaseKeyError, match="encrypt-db"):
        dbcrypt.check_database_file(plain, KEY)


def test_파일은_암호화됐는데_키가_없으면_키를_넣으라고_알려준다(tmp_path):
    path = _make_db(tmp_path / "itam.db", key=KEY)
    with pytest.raises(dbcrypt.DatabaseKeyError, match="ITAM_DB_KEY"):
        dbcrypt.check_database_file(path, None)


def test_키가_틀리면_시작하지_않는다(tmp_path):
    path = _make_db(tmp_path / "itam.db", key=KEY)
    with pytest.raises(dbcrypt.DatabaseKeyError, match="키가 틀렸"):
        dbcrypt.check_database_file(path, dbcrypt.new_key())


def test_처음_실행이면_그냥_넘어간다(tmp_path):
    dbcrypt.check_database_file(tmp_path / "없는파일.db", KEY)
    dbcrypt.check_database_file(tmp_path / "없는파일.db", None)


# --- 백업 --------------------------------------------------------------------------

def test_암호화된_DB_의_백업은_암호화된_채로_나온다(tmp_path, monkeypatch):
    source = _make_db(tmp_path / "itam.db", key=KEY, assets=9)
    monkeypatch.setattr(config, "DATABASE_URL", f"sqlite:///{source}")
    monkeypatch.setattr(config, "DB_KEY", KEY)

    result = backup.backup(tmp_path / "backups" / "itam-20260930.db")

    assert not dbcrypt.is_plaintext(result)
    assert "노트북".encode() not in result.read_bytes()
    assert dbcrypt.verify(result, KEY)["assets"] == 9


def test_예전_평문_백업들을_한꺼번에_암호화한다(tmp_path):
    folder = tmp_path / "backups"
    folder.mkdir()
    _make_db(folder / "itam-20260901-031700.db", assets=3)
    _make_db(folder / "itam-20260902-031700.db", assets=4)
    _make_db(folder / "itam-20260903-031700.db", key=KEY, assets=5)   # 이미 암호화됨
    (folder / "backup.log").write_text("백업 기록")                     # 백업이 아닌 파일

    done = dbcrypt.encrypt_directory(folder, KEY)

    assert done == ["itam-20260901-031700.db", "itam-20260902-031700.db"]
    for name, count in (("itam-20260901-031700.db", 3), ("itam-20260902-031700.db", 4),
                        ("itam-20260903-031700.db", 5)):
        assert not dbcrypt.is_plaintext(folder / name)
        assert dbcrypt.verify(folder / name, KEY)["assets"] == count
    assert (folder / "backup.log").read_text() == "백업 기록"
    assert not list(folder.glob("*.enc-tmp"))           # 임시 파일이 남지 않는다


# --- 명령행 ------------------------------------------------------------------------

def test_명령행으로_키를_만들고_확인한다(tmp_path, monkeypatch, capsys):
    assert dbcrypt.main(["dbcrypt", "new-key"]) == 0
    key = capsys.readouterr().out.strip()
    assert len(key) == 64

    path = _make_db(tmp_path / "itam.db", key=key, assets=2)
    monkeypatch.setenv("ITAM_DB_KEY", key)
    assert dbcrypt.main(["dbcrypt", "verify", str(path)]) == 0
    assert "암호화됨" in capsys.readouterr().out


def test_명령행에서_키가_틀리면_실패로_끝난다(tmp_path, monkeypatch, capsys):
    path = _make_db(tmp_path / "itam.db", key=KEY)
    monkeypatch.setenv("ITAM_DB_KEY", dbcrypt.new_key())
    assert dbcrypt.main(["dbcrypt", "verify", str(path)]) == 1
    assert "[오류]" in capsys.readouterr().err


def test_확인만_해도_백업_폴더에_부스러기_파일이_남지_않는다(tmp_path, monkeypatch):
    """복원 전에 백업을 열어 볼 때 -wal/-shm 이 생겨 쌓이면 안 된다."""
    source = _make_db(tmp_path / "live.db")
    monkeypatch.setattr(config, "DATABASE_URL", f"sqlite:///{source}")
    monkeypatch.setattr(config, "DB_KEY", None)
    folder = tmp_path / "backups"
    result = backup.backup(folder / "itam-20260930.db")

    assert dbcrypt.verify(result, None)["assets"] == 5
    assert sorted(p.name for p in folder.iterdir()) == ["itam-20260930.db"]
