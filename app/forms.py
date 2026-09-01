"""폼 입력값을 안전하게 파이썬 값으로 바꾸는 헬퍼."""

from datetime import date, datetime


def clean_str(value: str | None, max_length: int | None = None) -> str | None:
    """앞뒤 공백 제거. 빈 문자열은 None 으로 바꾼다."""
    if value is None:
        return None
    text = value.strip()
    if not text:
        return None
    if max_length is not None:
        text = text[:max_length]
    return text


def required_str(value: str | None, field_label: str, max_length: int | None = None) -> str:
    text = clean_str(value, max_length)
    if text is None:
        raise ValueError(f"{field_label}은(는) 필수 입력 항목입니다.")
    return text


def parse_date(value: str | None, field_label: str = "날짜") -> date | None:
    """'YYYY-MM-DD' 문자열을 date 로. 빈 값이면 None."""
    text = clean_str(value)
    if text is None:
        return None
    for fmt in ("%Y-%m-%d", "%Y/%m/%d", "%Y.%m.%d"):
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    raise ValueError(f"{field_label} 형식이 올바르지 않습니다. (예: 2026-01-31)")


def parse_money(value: str | None, field_label: str = "금액") -> float | None:
    """'1,200,000' 같은 입력을 숫자로."""
    text = clean_str(value)
    if text is None:
        return None
    text = text.replace(",", "").replace("원", "").strip()
    try:
        amount = float(text)
    except ValueError as exc:
        raise ValueError(f"{field_label}은(는) 숫자로 입력해 주세요.") from exc
    if amount < 0:
        raise ValueError(f"{field_label}은(는) 0 이상이어야 합니다.")
    return amount


def parse_int(value: str | None) -> int | None:
    text = clean_str(value)
    if text is None:
        return None
    try:
        return int(text)
    except ValueError:
        return None


def parse_choice(value: str | None, choices, field_label: str, default: str | None = None) -> str:
    """정해진 코드 값 중 하나인지 확인한다."""
    text = clean_str(value)
    if text is None:
        if default is not None:
            return default
        raise ValueError(f"{field_label}을(를) 선택해 주세요.")
    if text not in choices:
        raise ValueError(f"{field_label} 값이 올바르지 않습니다.")
    return text
