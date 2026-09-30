"""2단계 인증(TOTP)과 복구 코드.

인증 앱(Google Authenticator, Microsoft Authenticator, 1Password 등)이
30초마다 만들어 내는 6자리 숫자를 확인한다. 비밀번호가 새어 나가도
그 사람의 폰이 없으면 들어올 수 없다.

복구 코드는 폰을 잃어버렸을 때를 위한 것이다. 한 번 쓰면 사라진다.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets

import pyotp

ISSUER = "IT 자산관리"

# 인증 앱의 시계가 조금 어긋나도 되도록 앞뒤 한 칸(30초)을 허용한다
CLOCK_SKEW_WINDOW = 1

RECOVERY_CODE_COUNT = 8
RECOVERY_CODE_BYTES = 5   # 10자리 16진수


def new_secret() -> str:
    """인증 앱에 등록할 새 비밀키."""
    return pyotp.random_base32()


def provisioning_uri(secret: str, username: str) -> str:
    """인증 앱이 읽는 등록용 주소. 이 값을 QR 로 만들어 보여준다."""
    return pyotp.TOTP(secret).provisioning_uri(name=username, issuer_name=ISSUER)


def verify_code(secret: str, code: str) -> bool:
    """인증 앱이 보여준 6자리 코드가 맞는지 확인한다."""
    if not secret or not code:
        return False
    cleaned = code.strip().replace(" ", "").replace("-", "")
    if not cleaned.isdigit():
        return False
    return pyotp.TOTP(secret).verify(cleaned, valid_window=CLOCK_SKEW_WINDOW)


# --- 복구 코드 ----------------------------------------------------------------

def _hash_code(code: str) -> str:
    """복구 코드는 비밀번호와 마찬가지로 원문을 저장하지 않는다."""
    return hashlib.sha256(code.encode("utf-8")).hexdigest()


def new_recovery_codes() -> tuple[list[str], str]:
    """복구 코드 묶음을 만든다.

    사용자에게 보여줄 원문 목록과, DB 에 저장할 해시 문자열을 함께 돌려준다.
    원문은 이때 한 번만 보여주고 다시는 볼 수 없다.
    """
    codes = [secrets.token_hex(RECOVERY_CODE_BYTES).upper() for _ in range(RECOVERY_CODE_COUNT)]
    stored = " ".join(_hash_code(code) for code in codes)
    return codes, stored


def use_recovery_code(stored: str | None, code: str) -> str | None:
    """복구 코드가 맞으면 그 코드를 뺀 나머지를 돌려준다. 틀리면 None.

    한 번 쓴 코드는 목록에서 사라지므로 재사용할 수 없다.
    """
    if not stored or not code:
        return None

    candidate = _hash_code(code.strip().upper().replace(" ", "").replace("-", ""))
    remaining = stored.split()

    for index, saved in enumerate(remaining):
        if hmac.compare_digest(saved, candidate):
            del remaining[index]
            return " ".join(remaining)
    return None


def recovery_codes_left(stored: str | None) -> int:
    return len(stored.split()) if stored else 0
