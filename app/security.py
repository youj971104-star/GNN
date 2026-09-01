"""비밀번호 해싱과 검증.

외부 라이브러리 없이 표준 라이브러리의 PBKDF2-HMAC-SHA256 을 사용한다.
저장 형식: pbkdf2_sha256$<반복횟수>$<salt(hex)>$<hash(hex)>
"""

import hashlib
import hmac
import secrets

ALGORITHM = "pbkdf2_sha256"
ITERATIONS = 260_000
SALT_BYTES = 16

MIN_PASSWORD_LENGTH = 8


def hash_password(password: str, *, iterations: int = ITERATIONS) -> str:
    """평문 비밀번호를 저장 가능한 해시 문자열로 만든다."""
    salt = secrets.token_bytes(SALT_BYTES)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return f"{ALGORITHM}${iterations}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    """평문 비밀번호가 저장된 해시와 일치하는지 확인한다."""
    if not stored:
        return False
    try:
        algorithm, iterations_raw, salt_hex, digest_hex = stored.split("$")
        if algorithm != ALGORITHM:
            return False
        iterations = int(iterations_raw)
        salt = bytes.fromhex(salt_hex)
        expected = bytes.fromhex(digest_hex)
    except (ValueError, AttributeError):
        return False

    candidate = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return hmac.compare_digest(candidate, expected)


def validate_password(password: str) -> str | None:
    """비밀번호 정책 검사. 문제가 있으면 오류 메시지를, 없으면 None 을 반환한다."""
    if len(password) < MIN_PASSWORD_LENGTH:
        return f"비밀번호는 {MIN_PASSWORD_LENGTH}자 이상이어야 합니다."
    if password.isdigit():
        return "비밀번호에 숫자 외의 문자를 포함해 주세요."
    return None
