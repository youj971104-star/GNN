#!/usr/bin/env python3
"""개발용 실행 스크립트: python run.py

운영 배포는 README 의 '배포' 항목을 참고하세요.
"""

import os

import uvicorn

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host=os.getenv("ITAM_HOST", "0.0.0.0"),
        port=int(os.getenv("ITAM_PORT", "8000")),
        reload=os.getenv("ITAM_RELOAD", "1") == "1",
    )
