"""2단계 인증과 로그인 실패 제한 테스트."""

from datetime import datetime, timedelta, timezone

import pyotp
import pytest
from sqlalchemy import select

from app import config, twofactor
from app.models import User
from app.security import hash_password


def _code(secret: str) -> str:
    return pyotp.TOTP(secret).now()


@pytest.fixture
def admin(db) -> User:
    return db.scalar(select(User).where(User.username == "admin"))


# --- TOTP 계산 ----------------------------------------------------------------

def test_인증_앱_코드를_확인한다():
    secret = twofactor.new_secret()
    assert twofactor.verify_code(secret, _code(secret))
    assert not twofactor.verify_code(secret, "000000")


def test_숫자가_아니거나_빈_코드는_거부한다():
    secret = twofactor.new_secret()
    assert not twofactor.verify_code(secret, "abcdef")
    assert not twofactor.verify_code(secret, "")
    assert not twofactor.verify_code("", "123456")


def test_공백이나_하이픈이_섞여도_읽는다():
    secret = twofactor.new_secret()
    code = _code(secret)
    assert twofactor.verify_code(secret, f"{code[:3]} {code[3:]}")


def test_시계가_조금_어긋나도_통과한다():
    """인증 앱과 서버의 시계가 30초 정도 차이나는 일은 흔하다."""
    secret = twofactor.new_secret()
    totp = pyotp.TOTP(secret)
    past = totp.at(datetime.now(timezone.utc) - timedelta(seconds=30))
    assert twofactor.verify_code(secret, past)


def test_등록_주소에_계정과_서비스_이름이_들어간다():
    uri = twofactor.provisioning_uri("ABCDEFGHIJKLMNOP", "admin")
    assert uri.startswith("otpauth://totp/")
    assert "admin" in uri


# --- 복구 코드 ----------------------------------------------------------------

def test_복구_코드는_한_번_쓰면_사라진다():
    codes, stored = twofactor.new_recovery_codes()
    assert twofactor.recovery_codes_left(stored) == len(codes)

    remaining = twofactor.use_recovery_code(stored, codes[0])
    assert twofactor.recovery_codes_left(remaining) == len(codes) - 1
    assert twofactor.use_recovery_code(remaining, codes[0]) is None


def test_틀린_복구_코드는_받지_않는다():
    _, stored = twofactor.new_recovery_codes()
    assert twofactor.use_recovery_code(stored, "AAAAAAAAAA") is None
    assert twofactor.use_recovery_code(stored, "") is None
    assert twofactor.use_recovery_code(None, "AAAA") is None


def test_복구_코드_원문은_저장하지_않는다():
    codes, stored = twofactor.new_recovery_codes()
    for code in codes:
        assert code not in stored


# --- 로그인 흐름 ---------------------------------------------------------------

def test_2단계_인증이_꺼져_있으면_바로_로그인된다(client):
    response = client.post(
        "/login", data={"username": "admin", "password": "admin1234"}, follow_redirects=False
    )
    assert response.status_code == 303
    assert response.headers["location"] == "/"


def test_켜져_있으면_코드를_먼저_묻는다(client, db, admin):
    secret = twofactor.new_secret()
    admin.totp_secret = secret
    admin.totp_enabled = True
    db.commit()

    response = client.post(
        "/login", data={"username": "admin", "password": "admin1234"}, follow_redirects=False
    )
    assert response.status_code == 303
    assert response.headers["location"].startswith("/login/2fa")

    # 아직 로그인된 상태가 아니다
    assert client.get("/", follow_redirects=False).headers["location"].startswith("/login")

    ok = client.post("/login/2fa", data={"code": _code(secret)}, follow_redirects=False)
    assert ok.status_code == 303
    assert client.get("/").status_code == 200


def test_코드가_틀리면_들어갈_수_없다(client, db, admin):
    admin.totp_secret = twofactor.new_secret()
    admin.totp_enabled = True
    db.commit()

    client.post("/login", data={"username": "admin", "password": "admin1234"})
    response = client.post("/login/2fa", data={"code": "000000"})
    assert response.status_code == 401
    assert client.get("/", follow_redirects=False).headers["location"].startswith("/login")


def test_비밀번호_단계를_건너뛰고는_들어올_수_없다(client, db, admin):
    """/login/2fa 에 바로 들어가도 소용없어야 한다."""
    admin.totp_secret = twofactor.new_secret()
    admin.totp_enabled = True
    db.commit()

    response = client.get("/login/2fa", follow_redirects=False)
    assert response.headers["location"] == "/login"

    posted = client.post("/login/2fa", data={"code": _code(admin.totp_secret)}, follow_redirects=False)
    assert posted.headers["location"] == "/login"


def test_복구_코드로도_로그인된다(client, db, admin):
    codes, stored = twofactor.new_recovery_codes()
    admin.totp_secret = twofactor.new_secret()
    admin.totp_enabled = True
    admin.recovery_codes = stored
    db.commit()

    client.post("/login", data={"username": "admin", "password": "admin1234"})
    response = client.post("/login/2fa", data={"code": codes[0]}, follow_redirects=False)
    assert response.status_code == 303
    assert client.get("/").status_code == 200

    db.expire_all()
    assert twofactor.recovery_codes_left(db.get(User, admin.id).recovery_codes) == len(codes) - 1


def test_쓴_복구_코드는_다시_쓸_수_없다(client, db, admin):
    codes, stored = twofactor.new_recovery_codes()
    admin.totp_secret = twofactor.new_secret()
    admin.totp_enabled = True
    admin.recovery_codes = stored
    db.commit()

    client.post("/login", data={"username": "admin", "password": "admin1234"})
    client.post("/login/2fa", data={"code": codes[0]})
    client.post("/logout")

    client.post("/login", data={"username": "admin", "password": "admin1234"})
    again = client.post("/login/2fa", data={"code": codes[0]})
    assert again.status_code == 401


# --- 로그인 실패 제한 -----------------------------------------------------------

def test_여러_번_틀리면_계정이_잠긴다(client, db, admin):
    for _ in range(config.MAX_FAILED_LOGINS):
        client.post("/login", data={"username": "admin", "password": "틀린비밀번호"})

    db.expire_all()
    assert db.get(User, admin.id).is_locked()

    # 이제는 올바른 비밀번호를 넣어도 막힌다
    response = client.post("/login", data={"username": "admin", "password": "admin1234"})
    assert response.status_code == 429
    assert "잠겼습니다" in response.text


def test_로그인에_성공하면_실패_기록이_지워진다(client, db, admin):
    for _ in range(config.MAX_FAILED_LOGINS - 1):
        client.post("/login", data={"username": "admin", "password": "틀린비밀번호"})
    db.expire_all()
    assert db.get(User, admin.id).failed_logins == config.MAX_FAILED_LOGINS - 1

    client.post("/login", data={"username": "admin", "password": "admin1234"})
    db.expire_all()
    assert db.get(User, admin.id).failed_logins == 0


def test_잠금이_풀리면_다시_로그인된다(client, db, admin):
    admin.locked_until = datetime.now(timezone.utc) - timedelta(seconds=1)
    db.commit()

    response = client.post(
        "/login", data={"username": "admin", "password": "admin1234"}, follow_redirects=False
    )
    assert response.status_code == 303


def test_없는_아이디로는_잠금_기록을_남기지_않는다(client, db):
    """아이디가 실제로 있는지를 응답 차이로 알아낼 수 없어야 한다."""
    for _ in range(config.MAX_FAILED_LOGINS + 2):
        response = client.post("/login", data={"username": "없는계정", "password": "아무거나"})
        assert response.status_code == 401   # 잠김(429)이 아니라 늘 같은 응답


# --- 설정 화면 ----------------------------------------------------------------

def test_보안_설정_화면이_열린다(admin_client):
    response = admin_client.get("/me/security")
    assert response.status_code == 200
    assert "2단계 인증" in response.text


def test_등록_화면에_QR_과_비밀키가_나온다(admin_client, db, admin):
    response = admin_client.get("/me/security/2fa")
    assert response.status_code == 200
    assert "<svg" in response.text

    db.expire_all()
    secret = db.get(User, admin.id).totp_secret
    assert secret and secret in response.text
    assert not db.get(User, admin.id).totp_enabled   # 확인 전에는 켜지지 않는다


def test_코드를_확인해야_켜진다(admin_client, db, admin):
    admin_client.get("/me/security/2fa")
    db.expire_all()
    secret = db.get(User, admin.id).totp_secret

    wrong = admin_client.post("/me/security/2fa", data={"code": "000000"})
    assert wrong.status_code == 400
    db.expire_all()
    assert not db.get(User, admin.id).totp_enabled

    good = admin_client.post("/me/security/2fa", data={"code": _code(secret)})
    assert good.status_code == 200
    assert "복구 코드" in good.text
    db.expire_all()
    assert db.get(User, admin.id).totp_enabled
    assert twofactor.recovery_codes_left(db.get(User, admin.id).recovery_codes) == 8


def test_끄려면_비밀번호가_필요하다(admin_client, db, admin):
    admin.totp_secret = twofactor.new_secret()
    admin.totp_enabled = True
    db.commit()

    admin_client.post("/me/security/2fa/disable", data={"password": "틀린비밀번호"},
                      follow_redirects=False)
    db.expire_all()
    assert db.get(User, admin.id).totp_enabled

    admin_client.post("/me/security/2fa/disable", data={"password": "admin1234"},
                      follow_redirects=False)
    db.expire_all()
    account = db.get(User, admin.id)
    assert not account.totp_enabled
    assert account.totp_secret is None
    assert account.recovery_codes is None


def test_복구_코드를_새로_발급하면_이전_것은_무효(admin_client, db, admin):
    codes, stored = twofactor.new_recovery_codes()
    admin.totp_secret = twofactor.new_secret()
    admin.totp_enabled = True
    admin.recovery_codes = stored
    db.commit()

    response = admin_client.post("/me/security/recovery-codes", data={"password": "admin1234"})
    assert response.status_code == 200

    db.expire_all()
    new_stored = db.get(User, admin.id).recovery_codes
    assert twofactor.recovery_codes_left(new_stored) == 8
    assert twofactor.use_recovery_code(new_stored, codes[0]) is None   # 예전 코드는 안 먹는다


def test_비밀번호가_틀리면_복구_코드를_발급하지_않는다(admin_client, db, admin):
    _, stored = twofactor.new_recovery_codes()
    admin.totp_secret = twofactor.new_secret()
    admin.totp_enabled = True
    admin.recovery_codes = stored
    db.commit()

    admin_client.post("/me/security/recovery-codes", data={"password": "틀림"},
                      follow_redirects=False)
    db.expire_all()
    assert db.get(User, admin.id).recovery_codes == stored


def test_기존_계정은_2단계_인증이_꺼진_채로_시작한다(db):
    """이미 쓰던 계정이 갑자기 로그인 못 하게 되면 안 된다."""
    account = User(username="old", name="기존", password_hash=hash_password("oldpass123"))
    db.add(account)
    db.commit()

    assert not account.totp_enabled
    assert account.totp_secret is None
    assert account.failed_logins == 0
