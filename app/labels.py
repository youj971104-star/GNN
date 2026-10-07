"""자산 QR 라벨 생성.

자산마다 QR 을 만들어 라벨로 붙여 두면, 폰 기본 카메라로 찍는 것만으로
그 자산 화면이 열린다. QR 에는 자산 상세로 가는 짧은 주소를 담는다.

웹페이지가 직접 카메라를 켜려면 HTTPS 가 필요하지만, 이 방식은 폰의 카메라 앱이
주소를 열어 주는 것이라 HTTP 환경에서도 그대로 동작한다.
"""

from __future__ import annotations

import io
import re

import qrcode
import qrcode.image.svg

# SVG 앞에 붙는 XML 선언과 DOCTYPE. HTML 안에 넣을 때는 빼야 한다.
_XML_PROLOG = re.compile(r"<\?xml[^>]*\?>\s*|<!DOCTYPE[^>]*>\s*", re.IGNORECASE)


def short_path(asset_no: str) -> str:
    """QR 에 담을 짧은 경로. 예: /a/IT-2026-0001"""
    return f"/a/{asset_no}"


# QR 규격이 요구하는 둘레 여백(quiet zone)은 4칸이다.
# 이보다 좁으면 스캐너가 QR 의 경계를 잡지 못해 인식률이 크게 떨어진다.
QUIET_ZONE = 4


def qr_svg(data: str, *, box_size: int = 4, border: int = QUIET_ZONE) -> str:
    """QR 코드를 HTML 에 바로 넣을 수 있는 SVG 문자열로 만든다.

    box_size 는 한 칸의 크기, border 는 둘레 여백(칸 수)이다.
    라벨이 작아도 읽히도록 오류 정정 수준은 중간(M)을 쓴다.
    """
    code = qrcode.QRCode(
        version=None,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=box_size,
        border=border,
    )
    code.add_data(data)
    code.make(fit=True)

    image = code.make_image(image_factory=qrcode.image.svg.SvgPathImage)
    buffer = io.BytesIO()
    image.save(buffer)
    svg = buffer.getvalue().decode("utf-8")
    return _XML_PROLOG.sub("", svg).strip()
