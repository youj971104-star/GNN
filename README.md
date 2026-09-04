# IT 자산관리 시스템

사내 IT 자산(노트북·모니터·서버·소프트웨어 라이선스 등)의 **등록 · 지급 · 반납 · 현황 파악**을
한 곳에서 처리하는 사내 웹 애플리케이션입니다. 서버 한 대에 올려두면 IT 담당자와 현업 부서가
브라우저로 함께 사용할 수 있습니다.

* 기술 스택: **Python 3.11+ / FastAPI / SQLAlchemy / SQLite / Jinja2**
* 화면: 서버에서 HTML 을 그리는 방식이라 별도 프런트엔드 빌드가 필요 없습니다.
* 데이터: 기본은 파일 하나(`data/itam.db`)로 관리되며, 설정 한 줄로 PostgreSQL 로 옮길 수 있습니다.

---

## 주요 기능

### 1. 자산 관리
- 자산번호·자산명·분류·제조사·모델명·시리얼번호·사양·보관위치·도입일·취득가액·보증만료일·라이선스 키 등 관리
- 분류 9종(노트북 / 데스크톱 / 모니터 / 서버 / 네트워크 장비 / 모바일 기기 / 주변기기 / 소프트웨어 / 기타)
- 상태 5종(재고 / 사용중 / 수리중 / 분실 / 폐기)
- 검색어(자산번호·자산명·모델명·시리얼번호·제조사·보관위치·비고) + 분류·상태·부서·미지급 여부 필터, 정렬, 페이지네이션

### 2. 직원 지급 / 반납 이력
- 자산을 직원에게 지급하면 상태가 자동으로 '사용중'이 되고 지급 이력이 남습니다.
- 반납 시 반납일·반납 후 상태(재고/수리중/분실/폐기)·메모를 남기고 자산이 다시 지급 가능해집니다.
- 자산별·직원별로 전체 이력과 보유일수를 조회할 수 있습니다.
- 업무 규칙: 이미 지급된 자산 중복 지급 불가, 폐기·분실 자산 지급 불가, 퇴사자 지급 불가,
  미래 날짜 지급/반납 불가, 반납일이 지급일보다 빠를 수 없음, 자산을 보유한 직원은 퇴사 처리 불가

### 3. 사용자 로그인 / 권한
- 로그인 후에만 이용할 수 있으며, 비밀번호는 PBKDF2-SHA256 으로 해싱해 저장합니다.
- **관리자**: 자산·직원·계정 등록/수정/삭제, 지급·반납 처리, 엑셀 업로드
- **일반 사용자**: 조회와 엑셀 다운로드만 가능
- 활성화된 관리자 계정이 최소 1개는 유지되도록 보호합니다.

### 4. 엑셀 업로드 / 다운로드 + 대시보드
- 자산 목록·직원 목록·지급 이력을 엑셀(.xlsx)로 내려받습니다. **검색 조건이 그대로 반영**됩니다.
- 자산 등록 양식을 내려받아 채운 뒤 업로드하면 일괄 등록됩니다.
  이미 있는 자산번호는 갱신되고, `사용자 사번`을 채우면 지급 처리까지 함께 됩니다.
- 오류가 있는 행은 건너뛰고 나머지는 반영하며, 실패한 행 번호와 이유를 화면에 보여줍니다.
- 대시보드: 상태별·분류별·부서별 현황, 총 취득가액, 보증 만료 임박(90일 이내) 자산,
  퇴사자가 아직 보유 중인 자산, 최근 지급/반납 내역

---

## 내 컴퓨터에서 먼저 써보기

서버에 올리기 전에 본인 PC 에서 그대로 실행해 볼 수 있습니다. Docker 는 필요 없고,
**파이썬만 설치되어 있으면** 스크립트가 나머지를 알아서 준비합니다.

### 윈도우

1. 소스를 내려받아 압축을 풉니다.
   (`Code ▾ → Download ZIP`, 또는 `git clone`)
2. 폴더 안의 **`start-windows.bat`** 를 더블클릭합니다.
3. 파이썬이 없다면 설치 안내가 뜹니다. 설치할 때 화면 맨 아래
   **"Add python.exe to PATH"** 를 반드시 체크하고, 설치 후 다시 더블클릭하세요.
4. 잠시 뒤 브라우저가 자동으로 열립니다.

### macOS / 리눅스

```bash
git clone <저장소 주소>
cd GNN
./start.sh
```

### 실행하면

처음 한 번은 필요한 패키지를 받느라 1~2분 걸리고, 그 다음부터는 바로 뜹니다.
처음 실행할 때 샘플 데이터를 넣을지 물어보니, 둘러보실 거면 `y` 를 누르세요.

```
       http://localhost:8000

   최초 관리자 계정   아이디: admin   비밀번호: admin1234
```

| 항목 | 내용 |
| --- | --- |
| 종료 | 실행된 검은 창에서 `Ctrl+C` (또는 창 닫기) |
| 다시 실행 | 같은 파일을 다시 더블클릭 / `./start.sh` |
| 포트가 이미 사용 중 | `start-windows.bat 8001` / `./start.sh 8001` 처럼 뒤에 다른 번호를 붙이세요 |
| 데이터 위치 | 폴더 안 `data/itam.db` 파일 하나에 모두 저장됩니다 |
| 전부 지우고 다시 시작 | `data` 폴더를 지우고 다시 실행하면 빈 상태가 됩니다 |

> 이 방식은 **혼자 써보는 용도**입니다. 같은 PC 에서만 접속되고,
> PC 를 끄면 서비스도 멈춥니다. 여러 직원이 함께 쓰려면 아래 Docker 배포로 서버에 올리세요.

---

## 배포하기 (Docker · 권장)

서버에 Docker 만 설치되어 있으면 됩니다. Python 버전이나 패키지 충돌을 신경 쓸 필요가 없고,
리눅스·윈도우·클라우드 어디서든 같은 명령으로 동작합니다.

```bash
# 1. 소스 내려받기
git clone <저장소 주소>
cd GNN

# 2. 설정 파일 만들기 (최초 1회)
#    세션 키와 관리자 비밀번호가 자동으로 생성되어 화면에 표시됩니다.
./deploy.sh setup            # 다른 포트를 쓰려면: ./deploy.sh setup 9000

# 3. 시작
./deploy.sh start
```

끝나면 접속 주소가 화면에 표시됩니다.

```
  ✔ 정상적으로 시작되었습니다.

     사내망 접속 주소 : http://192.168.0.50:8000
     이 서버에서 확인 : http://localhost:8000
```

직원들에게는 이 **사내망 주소**를 알려주면 됩니다.
`./deploy.sh setup` 이 출력한 관리자 비밀번호로 로그인한 뒤,
우측 상단 **비밀번호 변경**에서 바로 바꿔 주세요.

### 운영 명령어

| 명령 | 하는 일 |
| --- | --- |
| `./deploy.sh start` | 서비스 시작 (필요하면 이미지도 빌드) |
| `./deploy.sh stop` | 서비스 중지 (**자산 데이터는 그대로 보존**) |
| `./deploy.sh restart` | 재시작 |
| `./deploy.sh status` | 실행 상태와 접속 주소 확인 |
| `./deploy.sh logs` | 실행 로그 보기 (Ctrl+C 로 종료) |
| `./deploy.sh update` | 코드를 받은 뒤 최신 버전으로 다시 빌드·재시작 |
| `./deploy.sh backup` | 데이터베이스 백업 → `backups/` 폴더에 저장 |
| `./deploy.sh restore <파일>` | 백업 시점으로 되돌리기 (되돌리기 전 현재 상태를 자동 백업) |
| `./deploy.sh doctor` | **접속이 안 될 때** 원인 진단 |
| `./deploy.sh demo` | 샘플 데이터 넣기 (처음 둘러볼 때만) |

### 접속이 안 될 때

먼저 진단 명령을 실행하면 원인을 순서대로 짚어 줍니다.

```bash
./deploy.sh doctor
```

```
  ✔ Docker 실행 중
  ✔ 설정 파일 확인 (접속 포트: 8000)
  ✔ 컨테이너 실행 중
  ✔ 서버 내부 응답 정상 (http://localhost:8000)
  ✔ 포트 연결 확인 (0.0.0.0:8000 → 컨테이너 8000)
  ✘ 방화벽(ufw)이 켜져 있는데 포트 8000 가 허용되어 있지 않습니다.
    → sudo ufw allow 8000/tcp
```

자주 겪는 원인은 다음과 같습니다.

| 증상 | 원인과 해결 |
| --- | --- |
| 서버에서는 되는데 **다른 PC 에서만** 안 된다 | 서버 방화벽이 포트를 막고 있는 경우가 가장 많습니다.<br>Ubuntu: `sudo ufw allow 8000/tcp`<br>RHEL/Rocky: `sudo firewall-cmd --permanent --add-port=8000/tcp && sudo firewall-cmd --reload`<br>클라우드(AWS·NCP 등)라면 **보안 그룹**에서도 열어야 합니다. |
| 아무 데서도 안 된다 | 서비스가 떠 있지 않을 수 있습니다. `./deploy.sh status` 로 확인하고, 문제가 있으면 `./deploy.sh logs` 로 원인을 봅니다. |
| 주소를 모르겠다 | `./deploy.sh doctor` 가 접속 가능한 주소를 모두 보여 줍니다. |
| 브라우저에 "연결이 비공개로 설정되어 있지 않습니다" | 주소 앞에 `https://` 가 아니라 `http://` 를 붙여야 합니다. HTTPS 는 도메인·인증서를 설정한 뒤에 쓸 수 있습니다. |
| 포트 8000 이 이미 사용 중이다 | 다른 포트로 다시 설정하세요. `.env` 의 `ITAM_PUBLIC_PORT` 를 바꾸고 `./deploy.sh restart` |
| 사내망 밖(집·외부)에서 접속하고 싶다 | 사내 VPN 을 통해 접속하거나, 사내 정책에 따라 별도 공개 설정이 필요합니다. 보안상 그냥 외부에 열어두는 것은 권장하지 않습니다. |

### 데이터는 어디에 있나요

자산·직원·이력 데이터는 `itam-data` 라는 **Docker 볼륨**에 저장됩니다.
`./deploy.sh stop`, `docker compose down`, 컨테이너 삭제·재생성, 이미지 재빌드 어느 경우에도
데이터는 그대로 남습니다.

### 백업

```bash
./deploy.sh backup
# ✔ 백업 완료: backups/itam-20260901-093012.db  (72K)
```

서비스를 멈추지 않고 안전하게 스냅샷을 뜹니다(SQLite 온라인 백업 API).
파일 하나가 곧 전체 데이터이므로, 이 파일만 사내 파일서버나 백업 스토리지에 보관하면 됩니다.

**매일 새벽 3시 자동 백업**을 걸고 싶다면 서버의 crontab 에 다음 한 줄을 추가하세요.

```cron
0 3 * * * cd /opt/itam && ./deploy.sh backup >> /var/log/itam-backup.log 2>&1
```

되돌릴 때는 백업 파일을 지정합니다. 실행 전에 확인 절차가 있고,
되돌리기 직전의 상태도 자동으로 백업해 둡니다.

```bash
./deploy.sh restore backups/itam-20260901-093012.db
```

### 버전 올리기

```bash
git pull
./deploy.sh update
```

### 나중에 사내 도메인 + HTTPS 로 바꾸려면

지금은 `http://<서버IP>:8000` 으로 쓰다가, 도메인과 인증서가 준비되면
**애플리케이션 코드 수정 없이** 전환할 수 있습니다.
인증서를 `deploy/certs/` 에 넣고, `.env` 의 `ITAM_HTTPS_ONLY=1` 로 바꾼 뒤:

```bash
docker compose --profile https up -d
```

자세한 절차는 [`deploy/README-HTTPS.md`](deploy/README-HTTPS.md) 를 참고하세요.

---

## 처음 도입할 때 권장 순서

1. **관리자 비밀번호 변경** — 우측 상단 `비밀번호 변경`
2. **직원 등록** — `직원 관리 > + 직원 등록`. 자산을 지급하려면 직원이 먼저 있어야 합니다.
3. **자산 등록** — 건수가 많으면 `엑셀 일괄 등록`에서 양식을 받아 한 번에 올리는 편이 빠릅니다.
   기존 자산 대장 엑셀이 있다면 양식의 열 이름에 맞춰 붙여넣으면 됩니다.
4. **지급 처리** — 자산 상세 화면 또는 `지급 / 반납 이력 > + 자산 지급`
5. **계정 발급** — 현업 부서에는 조회만 가능한 `일반 사용자` 계정을 만들어 주면 됩니다.

### 엑셀 양식 작성 규칙

| 항목 | 설명 |
| --- | --- |
| 자산번호 | **필수**. 고유 값. 이미 있으면 해당 자산이 갱신됩니다. |
| 자산명 | **필수** |
| 분류 / 상태 | 한글 이름(예: `노트북`, `재고`) 또는 영문 코드(`NOTEBOOK`, `IN_STOCK`) |
| 도입일 / 보증만료일 | `YYYY-MM-DD` (예: `2026-01-31`) |
| 취득가액 | 숫자. 쉼표를 넣어도 됩니다. |
| 사용자 사번 | 등록된 직원의 사번. 채우면 지급 처리되고 이력이 남습니다. 비우면 미지급 상태. |

---

## 부록 · Docker 를 쓸 수 없는 환경이라면

사내 정책 등으로 Docker 를 쓰지 못하는 경우, 리눅스 서버에 직접 올릴 수도 있습니다.

```bash
# 세션 키는 반드시 고정 값으로 지정해야 재시작 후에도 로그인이 유지됩니다
export ITAM_SECRET_KEY="$(python -c 'import secrets; print(secrets.token_hex(32))')"
export ITAM_ADMIN_PASSWORD="회사에서_정한_초기_비밀번호"

.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2
```

`systemd` 로 서비스 등록:

```ini
# /etc/systemd/system/itam.service
[Unit]
Description=IT 자산관리 시스템
After=network.target

[Service]
User=itam
WorkingDirectory=/opt/itam
EnvironmentFile=/opt/itam/.env
ExecStart=/opt/itam/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now itam
```

백업은 Docker 없이도 같은 명령으로 됩니다.

```bash
.venv/bin/python -m app.backup /backup/itam-$(date +%Y%m%d).db
```

HTTPS 를 적용했다면 `.env` 에 `ITAM_HTTPS_ONLY=1` 을 넣고, Nginx 설정은
[`deploy/nginx.conf`](deploy/nginx.conf) 를 참고하세요
(`proxy_pass` 주소만 `http://127.0.0.1:8000` 으로 바꾸면 됩니다).

### PostgreSQL 로 옮기기

```bash
pip install "psycopg[binary]"
export ITAM_DATABASE_URL="postgresql+psycopg://itam:비밀번호@db-host:5432/itam"
```

테이블은 첫 실행 시 자동으로 생성됩니다. 기존 데이터 이관은 별도 작업이 필요합니다.
이 경우 `./deploy.sh backup` 대신 `pg_dump` 를 사용하세요.

---

## 환경변수 목록

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `ITAM_SECRET_KEY` | 실행할 때마다 임의 생성 | 세션 서명 키. **운영에서는 반드시 고정** |
| `ITAM_DATABASE_URL` | `sqlite:///data/itam.db` | 데이터베이스 연결 주소 |
| `ITAM_DATA_DIR` | `./data` | SQLite 파일이 저장될 디렉터리 |
| `ITAM_ADMIN_USERNAME` | `admin` | 최초 생성되는 관리자 아이디 |
| `ITAM_ADMIN_PASSWORD` | `admin1234` | 최초 생성되는 관리자 비밀번호 |
| `ITAM_PAGE_SIZE` | `20` | 목록 한 페이지 행 수 |
| `ITAM_SESSION_MAX_AGE` | `43200` (12시간) | 로그인 유지 시간(초) |
| `ITAM_MAX_UPLOAD_BYTES` | `10485760` (10MB) | 엑셀 업로드 최대 크기 |
| `ITAM_HTTPS_ONLY` | `0` | `1` 이면 세션 쿠키를 HTTPS 로만 전송 (도메인+HTTPS 전환 시) |
| `ITAM_WORKERS` | `2` | 워커 프로세스 수 (Docker 실행 시) |
| `ITAM_PUBLIC_PORT` | `8000` | 서버 바깥에서 접속할 포트 (Docker 실행 시) |
| `ITAM_HOST` / `ITAM_PORT` | `0.0.0.0` / `8000` | `run.py` 로 실행할 때의 주소·포트 |

---

## 프로젝트 구조

```
app/
  main.py          앱 생성, 미들웨어, 시작 시 관리자 계정 준비
  config.py        환경변수 기반 설정
  database.py      DB 연결과 세션
  models.py        User / Employee / Asset / Assignment 모델과 코드 값
  security.py      비밀번호 해싱·검증 (PBKDF2-SHA256)
  deps.py          로그인 확인, 관리자 권한 검사
  forms.py         폼 입력값 검증 헬퍼
  services.py      검색·페이지네이션·지급/반납 규칙·대시보드 집계
  excel.py         엑셀 업로드/다운로드
  templating.py    Jinja2 설정, 화면용 필터, 안내 메시지
  routers/         화면별 라우터 (auth, dashboard, assets, employees, assignments, users)
  templates/       HTML 템플릿
  static/css/      스타일시트
  backup.py        데이터베이스 백업 (python -m app.backup)
tests/             pytest 테스트 (105개)
run.py             개발용 실행 스크립트
seed_demo.py       샘플 데이터 생성 스크립트

start-windows.bat  내 컴퓨터에서 실행 (윈도우, 더블클릭)
start.sh           내 컴퓨터에서 실행 (macOS / 리눅스)
deploy.sh          서버 배포·운영 명령 모음 (setup / start / backup / restore ...)
Dockerfile         운영용 이미지 정의
docker-compose.yml 서비스 실행 설정 (+ HTTPS 프로파일)
docker/            컨테이너 시작 스크립트
deploy/            Nginx 설정과 HTTPS 전환 안내
```

## 테스트

```bash
.venv/bin/python -m pytest tests/ -q
```

로그인·권한, 자산 CRUD, 지급/반납 업무 규칙, 엑셀 업로드/다운로드, 대시보드 집계,
데이터베이스 백업, 전 화면 렌더링까지 105개 테스트로 확인합니다.

## 데이터 모델 요약

| 테이블 | 설명 |
| --- | --- |
| `users` | 로그인 계정 (아이디, 해시된 비밀번호, 권한, 사용여부, 최근 로그인) |
| `employees` | 임직원 (사번, 이름, 부서, 직급, 연락처, 재직상태) |
| `assets` | 자산 (자산번호, 분류, 상태, 사양, 도입/보증 정보, 현재 사용자) |
| `assignments` | 지급/반납 이력 (자산, 대상 직원, 지급일, 반납일, 메모, 처리자) |

자산의 현재 사용자(`assets.holder_id`)와 미반납 이력(`assignments.returned_at IS NULL`)은
지급·반납 처리 시 항상 함께 갱신되어 서로 어긋나지 않습니다.
