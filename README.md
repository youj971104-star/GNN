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

## 빠르게 실행해 보기

```bash
# 1. 소스 내려받기
git clone <저장소 주소>
cd GNN

# 2. 가상환경 만들고 패키지 설치
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# 3. (선택) 샘플 데이터 넣기 - 화면을 먼저 둘러보고 싶을 때
python seed_demo.py

# 4. 실행
python run.py
```

브라우저에서 <http://localhost:8000> 접속 → 최초 관리자 계정으로 로그인합니다.

| 구분 | 아이디 | 비밀번호 |
| --- | --- | --- |
| 관리자 (자동 생성) | `admin` | `admin1234` |
| 조회 전용 (샘플 데이터 실행 시) | `viewer` | `viewer1234` |

> **첫 로그인 후 우측 상단 '비밀번호 변경'에서 반드시 비밀번호를 바꾸세요.**
> 기본 비밀번호는 `ITAM_ADMIN_PASSWORD` 환경변수로도 지정할 수 있습니다.

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

## 운영 서버에 배포하기

### 1) 환경변수 설정

`.env.example` 을 참고해 최소한 아래 두 가지는 반드시 지정하세요.

```bash
export ITAM_SECRET_KEY="$(python -c 'import secrets; print(secrets.token_hex(32))')"
export ITAM_ADMIN_PASSWORD="회사에서_정한_초기_비밀번호"
```

`ITAM_SECRET_KEY` 를 지정하지 않으면 서버를 재시작할 때마다 값이 새로 만들어져
**모든 사용자의 로그인이 풀립니다.**

### 2) 실행

```bash
# 워커 4개로 실행 (개발용 자동 리로드 없음)
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
```

`systemd` 서비스 예시:

```ini
# /etc/systemd/system/itam.service
[Unit]
Description=IT 자산관리 시스템
After=network.target

[Service]
User=itam
WorkingDirectory=/opt/itam
EnvironmentFile=/opt/itam/.env
ExecStart=/opt/itam/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
Restart=always

[Install]
WantedBy=multi-user.target
```

### 3) HTTPS 사용 시

Nginx 등 리버스 프록시 뒤에 두고 HTTPS 를 적용했다면,
`app/main.py` 의 `SessionMiddleware` 설정에서 `https_only=True` 로 바꿔 주세요.
세션 쿠키가 HTTPS 로만 전송되어 더 안전합니다.

### 4) 백업

SQLite 를 쓰는 경우 **`data/itam.db` 파일 하나만 복사하면 전체 백업**입니다.
운영 중에도 안전하게 백업하려면:

```bash
sqlite3 data/itam.db ".backup '/backup/itam-$(date +%Y%m%d).db'"
```

### 5) PostgreSQL 로 옮기기

```bash
pip install "psycopg[binary]"
export ITAM_DATABASE_URL="postgresql+psycopg://itam:비밀번호@db-host:5432/itam"
```

테이블은 첫 실행 시 자동으로 생성됩니다. 기존 데이터 이관은 별도 작업이 필요합니다.

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
tests/             pytest 테스트 (96개)
run.py             개발용 실행 스크립트
seed_demo.py       샘플 데이터 생성 스크립트
```

## 테스트

```bash
.venv/bin/python -m pytest tests/ -q
```

로그인·권한, 자산 CRUD, 지급/반납 업무 규칙, 엑셀 업로드/다운로드, 대시보드 집계,
전 화면 렌더링까지 96개 테스트로 확인합니다.

## 데이터 모델 요약

| 테이블 | 설명 |
| --- | --- |
| `users` | 로그인 계정 (아이디, 해시된 비밀번호, 권한, 사용여부, 최근 로그인) |
| `employees` | 임직원 (사번, 이름, 부서, 직급, 연락처, 재직상태) |
| `assets` | 자산 (자산번호, 분류, 상태, 사양, 도입/보증 정보, 현재 사용자) |
| `assignments` | 지급/반납 이력 (자산, 대상 직원, 지급일, 반납일, 메모, 처리자) |

자산의 현재 사용자(`assets.holder_id`)와 미반납 이력(`assignments.returned_at IS NULL`)은
지급·반납 처리 시 항상 함께 갱신되어 서로 어긋나지 않습니다.
