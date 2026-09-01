"""로그인 / 권한 관련 테스트."""

from app.models import User
from app.security import hash_password, validate_password, verify_password


def test_비밀번호_해시는_원문을_노출하지_않고_검증된다():
    stored = hash_password("s3cret-pass")
    assert "s3cret-pass" not in stored
    assert verify_password("s3cret-pass", stored)
    assert not verify_password("wrong-pass", stored)


def test_같은_비밀번호도_매번_다른_해시가_된다():
    assert hash_password("samepass1") != hash_password("samepass1")


def test_비밀번호_정책():
    assert validate_password("short") is not None
    assert validate_password("12345678") is not None  # 숫자만
    assert validate_password("goodpass1") is None


def test_로그인하지_않으면_로그인_화면으로_보낸다(client):
    response = client.get("/assets", follow_redirects=False)
    assert response.status_code == 303
    assert response.headers["location"].startswith("/login")


def test_기본_관리자_계정이_자동_생성된다(client, db):
    admin = db.query(User).filter(User.username == "admin").one()
    assert admin.role == "ADMIN"
    assert admin.is_active


def test_잘못된_비밀번호는_로그인_실패(client):
    response = client.post("/login", data={"username": "admin", "password": "틀린비밀번호"})
    assert response.status_code == 401
    assert "올바르지 않습니다" in response.text


def test_로그인_성공하면_대시보드를_볼_수_있다(admin_client):
    response = admin_client.get("/")
    assert response.status_code == 200
    assert "대시보드" in response.text


def test_로그아웃하면_세션이_끊긴다(admin_client):
    admin_client.post("/logout", follow_redirects=False)
    response = admin_client.get("/", follow_redirects=False)
    assert response.status_code == 303
    assert response.headers["location"].startswith("/login")


def test_일반_사용자는_자산을_등록할_수_없다(viewer_client):
    response = viewer_client.get("/assets/new")
    assert response.status_code == 403
    assert "관리자" in response.text


def test_일반_사용자도_목록은_조회할_수_있다(viewer_client):
    assert viewer_client.get("/assets").status_code == 200
    assert viewer_client.get("/employees").status_code == 200
    assert viewer_client.get("/assignments").status_code == 200


def test_일반_사용자는_계정_관리에_접근할_수_없다(viewer_client):
    assert viewer_client.get("/users").status_code == 403


def test_외부_주소로는_리다이렉트하지_않는다(client):
    response = client.post(
        "/login",
        data={"username": "admin", "password": "admin1234", "next": "https://evil.example.com"},
        follow_redirects=False,
    )
    assert response.headers["location"] == "/"


def test_비밀번호_변경(admin_client):
    response = admin_client.post(
        "/me/password",
        data={
            "current_password": "admin1234",
            "new_password": "newpass1234",
            "confirm_password": "newpass1234",
        },
        follow_redirects=False,
    )
    assert response.status_code == 303

    admin_client.post("/logout")
    failed = admin_client.post("/login", data={"username": "admin", "password": "admin1234"})
    assert failed.status_code == 401
    ok = admin_client.post(
        "/login", data={"username": "admin", "password": "newpass1234"}, follow_redirects=False
    )
    assert ok.status_code == 303
