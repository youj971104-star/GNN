"""QR·바코드로 읽은 값에서 자산번호를 찾아낸다.

라벨의 QR 에는 주소가 들어 있다.

    https://ourcompany.duckdns.org/a/0121   →  0121

주소 말고 자산번호만 들어 있는 바코드(장비에 원래 붙어 있던 것 등)도 있고,
사람이 직접 입력하는 경우도 있다. 어느 쪽이든 같은 자리에서 받아 준다.
"""

from __future__ import annotations

from urllib.parse import unquote, urlparse

# QR 라벨이 쓰는 짧은 주소
SHORT_PREFIX = "/a/"
# 자산 상세 주소를 그대로 찍은 경우 (/assets/12)
DETAIL_PREFIX = "/assets/"

MAX_CODE_LENGTH = 300


def parse_scanned_code(text: str | None) -> str | None:
    """읽은 값에서 자산번호를 꺼낸다. 알아볼 수 없으면 None.

    자산번호가 아니라 상세 화면 주소(/assets/12)를 찍었다면 그 값은 자산 id 라
    번호가 아니다. 그건 여기서 다루지 않고 라우터가 id 로 찾는다.
    """
    if not text:
        return None

    value = text.strip()
    if not value or len(value) > MAX_CODE_LENGTH:
        return None

    # 주소 형태면 경로만 본다
    if "://" in value:
        path = urlparse(value).path
    elif value.startswith("/"):
        path = value
    else:
        # 주소가 아니면 값 자체가 자산번호다
        return value if _looks_like_asset_no(value) else None

    path = unquote(path.rstrip("/"))
    if SHORT_PREFIX in path:
        candidate = path.rsplit(SHORT_PREFIX, 1)[1]
        return candidate if _looks_like_asset_no(candidate) else None
    return None


def parse_asset_id(text: str | None) -> int | None:
    """찍은 값이 자산 상세 주소(/assets/12)면 그 id."""
    if not text:
        return None

    value = text.strip()
    if "://" in value:
        path = urlparse(value).path
    elif value.startswith("/"):
        path = value
    else:
        return None

    path = path.rstrip("/")
    if DETAIL_PREFIX not in path:
        return None

    tail = path.rsplit(DETAIL_PREFIX, 1)[1]
    return int(tail) if tail.isdigit() else None


def _looks_like_asset_no(value: str) -> bool:
    """자산번호로 볼 수 있는 값인지.

    번호 체계는 회사마다 달라서 형식을 따지지 않는다.
    다만 줄바꿈이나 공백이 섞인 값은 잘못 읽은 것으로 본다.
    """
    if not value or len(value) > 50:
        return False
    return not any(ch.isspace() for ch in value)
