"""deploy.sh 가 컨테이너 안에서 부르는 명령.

컨테이너의 프로그램 코드는 /app 에 있다. 셸에서 'cd /data' 로 옮겨 간 뒤
'python -m app.…' 을 부르면 코드를 찾지 못해 'No module named app' 으로 실패한다.
encrypt-db 가 실제 서버에서 이렇게 실패했다.
"""

import pathlib
import re

DEPLOY = pathlib.Path("deploy.sh").read_text()
DOCKERFILE = pathlib.Path("Dockerfile").read_text()


def _sh_blocks():
    """'$DC run ... sh "$SERVICE" -c "…"' 블록들 (실행 옵션 + 스크립트)."""
    return re.findall(r'(\$DC run [^\n]*--entrypoint sh "\$SERVICE" -c \\\n\s*"(?:[^"\\]|\\.)*")', DEPLOY)


def test_컨테이너_셸_블록을_찾는다():
    assert len(_sh_blocks()) >= 2          # encrypt-db, restore


def test_다른_폴더로_옮겨_가서_파이썬을_부르면_코드_위치를_알려_준다():
    for block in _sh_blocks():
        if "cd /" in block and "python -m app." in block:
            assert "PYTHONPATH=/app" in block, block[:120]


def test_이미지도_코드_위치를_알고_있다():
    assert "PYTHONPATH=/app" in DOCKERFILE
