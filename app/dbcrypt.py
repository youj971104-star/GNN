"""데이터베이스 파일 암호화 (SQLCipher).

서버에 들어온 사람이나 백업 파일을 가져간 사람이 파일만으로는 내용을 볼 수
없게 한다. 파일 전체가 AES-256 으로 암호화되어, 키 없이 열면 머리부터 무작위
바이트로 보인다.

키는 64자리 16진수(256비트)이고 .env 의 ITAM_DB_KEY 에 둔다. 비워 두면 예전처럼
암호화하지 않는다. **키를 잃어버리면 데이터와 백업을 영영 열 수 없다.**

    python -m app.dbcrypt new-key                 새 키 만들기
    python -m app.dbcrypt encrypt <평문> <결과>   평문 DB 를 암호화한 사본 만들기
    python -m app.dbcrypt decrypt <암호> <결과>   (다른 곳으로 옮길 때) 평문 사본 만들기
    python -m app.dbcrypt verify <파일>           키로 열어 무결성·건수 확인
    python -m app.dbcrypt encrypt-dir <폴더>      폴더 안 평문 백업을 모두 암호화

encrypt/decrypt/verify 는 ITAM_DB_KEY 환경변수의 키를 쓴다.
"""

from __future__ import annotations

import os
import re
import secrets
import sqlite3
import sys
from pathlib import Path

KEY_HEX_LENGTH = 64
PLAIN_HEADER = b"SQLite format 3\x00"

_KEY_PATTERN = re.compile(r"^[0-9a-fA-F]{64}$")


class DatabaseKeyError(RuntimeError):
    """키가 없거나, 틀렸거나, 파일과 설정이 맞지 않을 때."""


# --- 키 -----------------------------------------------------------------------

def new_key() -> str:
    return secrets.token_hex(KEY_HEX_LENGTH // 2)


def validate_key(key: str | None) -> str:
    if not key or not _KEY_PATTERN.match(key.strip()):
        raise DatabaseKeyError(
            "ITAM_DB_KEY 는 64자리 16진수여야 합니다. "
            "'python -m app.dbcrypt new-key' 로 만든 값을 넣어 주세요."
        )
    return key.strip().lower()


def key_pragma(key: str) -> str:
    """원시 256비트 키를 넣는 PRAGMA.

    암호 문구 대신 원시 키를 쓰면 연결할 때마다 거치는 키 유도(PBKDF2)를
    건너뛴다. 키 자체가 무작위 256비트라 유도가 필요 없고, 작은 서버에서도
    연결이 빠르다.
    """
    return f"PRAGMA key = \"x'{validate_key(key)}'\""


def driver():
    """SQLCipher 파이썬 드라이버. 없으면 이유를 알려 준다."""
    try:
        from sqlcipher3 import dbapi2
    except ImportError as exc:   # pragma: no cover - 설치 환경에 따라 다르다
        raise DatabaseKeyError(
            "데이터베이스 암호화에 필요한 sqlcipher3 가 설치되어 있지 않습니다.\n"
            "  - 서버(Docker)라면 './deploy.sh update' 로 이미지를 다시 만드세요.\n"
            "  - 암호화는 리눅스 x86_64 에서만 지원합니다(ARM·윈도우·맥 제외)."
        ) from exc
    return dbapi2


# --- 파일 --------------------------------------------------------------------

def is_plaintext(path: Path | str) -> bool:
    """암호화되지 않은 SQLite 파일인지 (파일 머리로 판단)."""
    with open(path, "rb") as f:
        return f.read(len(PLAIN_HEADER)) == PLAIN_HEADER


def connect(path: Path | str, key: str):
    """암호화된 DB 를 열고, 키가 맞는지까지 확인한다."""
    conn = driver().connect(str(path))
    conn.execute(key_pragma(key))
    try:
        conn.execute("SELECT count(*) FROM sqlite_master").fetchone()
    except Exception as exc:
        conn.close()
        raise DatabaseKeyError(
            f"'{path}' 를 열 수 없습니다. 키가 틀렸거나 암호화된 파일이 아닙니다."
        ) from exc
    return conn


def check_database_file(path: Path | str, key: str | None) -> None:
    """서비스를 띄우기 전에, 파일과 설정이 서로 맞는지 확인한다.

    맞지 않으면 SQLite 는 'file is not a database' 라고만 한다. 무엇을 해야
    하는지 알 수 있게 미리 걸러 말해 준다.
    """
    path = Path(path)
    if not path.exists() or path.stat().st_size == 0:
        return   # 처음 실행 - 설정대로 새로 만들어진다

    plain = is_plaintext(path)
    if key and plain:
        raise DatabaseKeyError(
            "ITAM_DB_KEY 가 설정되어 있는데 데이터베이스 파일은 아직 암호화되지 않았습니다.\n"
            "  './deploy.sh encrypt-db' 로 변환하거나, .env 에서 ITAM_DB_KEY 를 지우세요."
        )
    if not key and not plain:
        raise DatabaseKeyError(
            "데이터베이스 파일이 암호화되어 있는데 ITAM_DB_KEY 가 없습니다.\n"
            "  .env 에 암호화할 때 쓴 키를 ITAM_DB_KEY=... 로 넣어 주세요."
        )
    if key:
        connect(path, key).close()   # 키가 맞는지까지 본다


def table_counts(conn) -> dict[str, int]:
    """표마다 행 수. 변환 전후가 같은지 확인하는 데 쓴다."""
    names = [
        row[0]
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name"
        )
    ]
    return {name: conn.execute(f'SELECT count(*) FROM "{name}"').fetchone()[0] for name in names}


def _integrity(conn) -> str:
    return conn.execute("PRAGMA integrity_check").fetchone()[0]


def encrypt_file(source: Path | str, destination: Path | str, key: str) -> dict[str, int]:
    """평문 DB 를 암호화한 사본을 만든다. 원본은 건드리지 않는다.

    만든 뒤 다시 열어 무결성과 표마다의 건수가 원본과 같은지 확인한다.
    """
    source, destination = Path(source), Path(destination)
    if not is_plaintext(source):
        raise DatabaseKeyError(f"'{source}' 는 이미 암호화되어 있거나 SQLite 파일이 아닙니다.")
    if destination.exists():
        destination.unlink()

    # 원본은 키 없이(평문으로) 연다. WAL 에만 있는 최신 내용까지 함께 읽힌다.
    conn = driver().connect(str(source))
    try:
        before = table_counts(conn)
        conn.execute(
            f"ATTACH DATABASE ? AS encrypted KEY \"x'{validate_key(key)}'\"",
            (str(destination),),
        )
        conn.execute("SELECT sqlcipher_export('encrypted')")
        # 버전 번호(마이그레이션 판단에 쓰일 수 있다)도 그대로 옮긴다
        version = conn.execute("PRAGMA user_version").fetchone()[0]
        conn.execute(f"PRAGMA encrypted.user_version = {int(version)}")
        conn.execute("DETACH DATABASE encrypted")
    finally:
        conn.close()

    return _verify_copy(destination, key, before)


def decrypt_file(source: Path | str, destination: Path | str, key: str) -> dict[str, int]:
    """암호화된 DB 의 평문 사본을 만든다 (다른 환경으로 옮길 때만)."""
    source, destination = Path(source), Path(destination)
    if destination.exists():
        destination.unlink()

    conn = connect(source, key)
    try:
        before = table_counts(conn)
        conn.execute("ATTACH DATABASE ? AS plaintext KEY ''", (str(destination),))
        conn.execute("SELECT sqlcipher_export('plaintext')")
        conn.execute("DETACH DATABASE plaintext")
    finally:
        conn.close()

    with sqlite3.connect(destination) as check:
        if _integrity(check) != "ok" or table_counts(check) != before:
            raise DatabaseKeyError("평문 사본을 확인하지 못했습니다.")
    return before


def _verify_copy(path: Path, key: str, expected: dict[str, int]) -> dict[str, int]:
    conn = connect(path, key)
    try:
        if _integrity(conn) != "ok":
            raise DatabaseKeyError(f"'{path}' 무결성 검사에 실패했습니다.")
        after = table_counts(conn)
    finally:
        conn.close()
    if after != expected:
        raise DatabaseKeyError(f"변환 전후 건수가 다릅니다: {expected} → {after}")
    return after


def verify(path: Path | str, key: str | None) -> dict[str, int]:
    """파일을 열어 무결성을 확인하고 표마다 건수를 돌려준다."""
    path = Path(path)
    if is_plaintext(path):
        # immutable: 읽기만 하고 -wal/-shm 같은 보조 파일을 만들지 않는다.
        # 백업 파일은 쓰는 중인 파일이 아니라서 이렇게 열어도 된다.
        conn = sqlite3.connect(f"file:{path}?mode=ro&immutable=1", uri=True)
    else:
        if not key:
            raise DatabaseKeyError(f"'{path}' 는 암호화되어 있습니다. ITAM_DB_KEY 가 필요합니다.")
        conn = connect(path, key)
    try:
        if _integrity(conn) != "ok":
            raise DatabaseKeyError(f"'{path}' 무결성 검사에 실패했습니다.")
        return table_counts(conn)
    finally:
        conn.close()


def encrypt_directory(folder: Path | str, key: str) -> list[str]:
    """폴더 안의 평문 백업(itam-*.db)을 모두 암호화한다.

    하나씩 암호화한 사본을 만들어 건수를 확인한 뒤에야 원본과 바꾼다.
    중간에 실패해도 원본은 남는다.
    """
    done = []
    for path in sorted(Path(folder).glob("itam-*.db")):
        if not is_plaintext(path):
            continue
        temp = path.with_suffix(".db.enc-tmp")
        encrypt_file(path, temp, key)
        os.replace(temp, path)
        done.append(path.name)
    return done


# --- 명령행 --------------------------------------------------------------------

def _env_key() -> str:
    key = os.environ.get("ITAM_DB_KEY", "").strip()
    if not key:
        raise DatabaseKeyError("ITAM_DB_KEY 환경변수가 비어 있습니다.")
    return validate_key(key)


def _summary(counts: dict[str, int]) -> str:
    return ", ".join(f"{name} {count}" for name, count in counts.items())


def main(argv: list[str]) -> int:
    usage = (
        "사용법: python -m app.dbcrypt new-key | encrypt <평문> <결과> | "
        "decrypt <암호> <결과> | verify <파일> | encrypt-dir <폴더>"
    )
    if len(argv) < 2:
        print(usage, file=sys.stderr)
        return 2

    command, args = argv[1], argv[2:]
    try:
        if command == "new-key" and not args:
            print(new_key())
        elif command == "encrypt" and len(args) == 2:
            print("암호화 완료 -", _summary(encrypt_file(args[0], args[1], _env_key())))
        elif command == "decrypt" and len(args) == 2:
            print("평문 사본 완료 -", _summary(decrypt_file(args[0], args[1], _env_key())))
        elif command == "verify" and len(args) == 1:
            key = os.environ.get("ITAM_DB_KEY", "").strip() or None
            state = "평문" if is_plaintext(args[0]) else "암호화됨"
            print(f"정상 ({state}) -", _summary(verify(args[0], key)))
        elif command == "encrypt-dir" and len(args) == 1:
            names = encrypt_directory(args[0], _env_key())
            print(f"백업 {len(names)}개를 암호화했습니다.")
        else:
            print(usage, file=sys.stderr)
            return 2
    except DatabaseKeyError as exc:
        print(f"[오류] {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
