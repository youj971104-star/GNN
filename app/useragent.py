"""접속한 브라우저가 '앱 안의 브라우저'인지 알아본다.

카카오톡·네이버 같은 앱에서 QR 을 찍으면 그 앱 전용 브라우저가 열린다.
앱 전용 브라우저는 쿠키를 따로 보관하고 창을 닫으면 지우는 경우가 많아,
찍을 때마다 다시 로그인하게 된다. 그래서 로그인 화면에서 안내해 주고,
폰 기본 카메라로 찍도록 권한다.
"""

from __future__ import annotations

import re

# (사용자 에이전트에 들어 있는 표시, 사람에게 보여 줄 이름)
IN_APP_BROWSERS = (
    ("KAKAOTALK", "카카오톡"),
    ("KAKAOSTORY", "카카오스토리"),
    ("NAVER(INAPP", "네이버"),
    ("NAVER(IN-APP", "네이버"),
    ("WHALE/", "네이버 웨일"),      # 웨일 자체는 문제없지만 인앱 웨일뷰가 섞여 온다
    ("DAUMAPPS", "다음"),
    ("LINE/", "라인"),
    ("INSTAGRAM", "인스타그램"),
    ("FBAV", "페이스북"),
    ("FB_IAB", "페이스북"),
    ("EVERYTIMEAPP", "에브리타임"),
)

# 웨일 브라우저 자체로 접속한 경우는 앱 안의 브라우저가 아니다
_REAL_BROWSER_HINTS = ("WHALE/", )


def in_app_browser(user_agent: str | None) -> str | None:
    """앱 안의 브라우저면 그 앱 이름, 아니면 None."""
    if not user_agent:
        return None
    ua = user_agent.upper()

    for token, name in IN_APP_BROWSERS:
        if token not in ua:
            continue
        # 웨일은 'inapp' 표시가 함께 있을 때만 앱 안의 브라우저로 본다
        if token in _REAL_BROWSER_HINTS and "INAPP" not in ua and "IN-APP" not in ua:
            continue
        return name
    return None


def is_android(user_agent: str | None) -> bool:
    return bool(user_agent) and "ANDROID" in user_agent.upper()


def chrome_intent_url(url: str) -> str:
    """같은 주소를 안드로이드 크롬으로 다시 여는 링크.

    앱 안의 브라우저에서 이 링크를 누르면 크롬이 열리고, 크롬에 저장된
    로그인이 그대로 쓰인다. 아이폰에는 이런 방법이 없어 안내만 한다.
    """
    scheme = "https" if url.startswith("https://") else "http"
    without_scheme = re.sub(r"^https?://", "", url)
    return f"intent://{without_scheme}#Intent;scheme={scheme};package=com.android.chrome;end"
