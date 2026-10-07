# IT 자산관리 시스템 - 운영용 이미지
FROM python:3.11-slim

# 파이썬 기본 설정
#  - PYTHONDONTWRITEBYTECODE: .pyc 파일을 만들지 않아 이미지가 깔끔해진다
#  - PYTHONUNBUFFERED: 로그가 버퍼에 쌓이지 않고 바로 출력된다 (docker logs 용)
#  - TZ: 화면에 표시되는 등록일/수정일을 한국 시간 기준으로 맞춘다
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TZ=Asia/Seoul

# 추가 패키지를 설치하지 않는다.
#  - 시간대 정보는 베이스 이미지에 이미 들어 있다
#  - 상태 확인과 DB 백업은 파이썬 표준 라이브러리로 처리한다 (app/backup.py)
# 덕분에 이미지가 가볍고, 사내망처럼 외부 접속이 제한된 환경에서도 빌드가 잘 된다.

WORKDIR /app

# 의존성만 먼저 설치해 두면, 코드만 바뀌었을 때 재빌드가 훨씬 빨라진다
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/
COPY seed_demo.py run.py ./
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 컨테이너 안에서 root 로 돌지 않도록 전용 계정을 만든다
RUN useradd --create-home --uid 10001 itam \
    && mkdir -p /data \
    && chown -R itam:itam /app /data
USER itam

# DB 파일은 /data 에 두고, 이 경로를 볼륨으로 붙여 데이터를 보존한다
ENV ITAM_DATA_DIR=/data \
    ITAM_DATABASE_URL=sqlite:////data/itam.db \
    ITAM_HOST=0.0.0.0 \
    ITAM_PORT=8000 \
    ITAM_WORKERS=2

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD ["python", "-c", "import urllib.request as u; u.urlopen('http://127.0.0.1:8000/healthz', timeout=4)"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
