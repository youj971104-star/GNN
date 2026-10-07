"""뒤로 가기 버튼과 직원 빠른 등록 팝업 테스트."""

import pytest
from sqlalchemy import select

from app.models import Asset, Employee

# (경로, 버튼을 눌렀을 때 가야 할 상위 화면)
PAGES_WITH_BACK = [
    ("/assets", "/"),
    ("/assets/new", "/assets"),
    ("/assets/labels", "/assets"),
    ("/assets/import", "/assets"),
    ("/employees", "/"),
    ("/employees/new", "/employees"),
    ("/employees/import", "/employees"),
    ("/assignments", "/"),
    ("/assignments/new", "/assignments"),
    ("/maintenance", "/"),
    ("/users", "/"),
    ("/users/new", "/users"),
    ("/me/security", "/"),
    ("/me/password", "/me/security"),
    ("/me/security/2fa", "/me/security"),
]


# --- 뒤로 가기 버튼 ------------------------------------------------------------

@pytest.mark.parametrize("path,parent", PAGES_WITH_BACK)
def test_모든_화면에_뒤로_버튼이_있다(admin_client, path, parent):
    response = admin_client.get(path)
    assert response.status_code == 200
    assert "data-back" in response.text, f"{path} 에 뒤로 버튼이 없습니다"
    assert f'href="{parent}"' in response.text, f"{path} 의 상위 경로가 {parent} 가 아닙니다"


def test_대시보드에는_뒤로_버튼이_없다(admin_client):
    """첫 화면이라 돌아갈 곳이 없다."""
    assert "data-back" not in admin_client.get("/").text


def test_상세_화면의_상위는_목록이다(admin_client, db, asset, employee):
    assert f'href="/assets"' in admin_client.get(f"/assets/{asset.id}").text
    assert f'href="/employees"' in admin_client.get(f"/employees/{employee.id}").text


def test_수정_화면은_그_항목의_상세로_돌아간다(admin_client, asset, employee):
    """목록이 아니라 방금 보던 항목으로 돌아가는 편이 자연스럽다."""
    assert f'href="/assets/{asset.id}"' in admin_client.get(f"/assets/{asset.id}/edit").text
    assert f'href="/employees/{employee.id}"' in admin_client.get(
        f"/employees/{employee.id}/edit"
    ).text


def test_뒤로_버튼_스크립트가_서빙된다(admin_client):
    response = admin_client.get("/static/js/back-button.js")
    assert response.status_code == 200
    assert "history.back" in response.text


def test_자바스크립트가_없어도_링크로_동작한다(admin_client):
    """href 가 비어 있으면 스크립트가 꺼진 환경에서 아무 데도 못 간다."""
    page = admin_client.get("/assets/new").text
    assert 'href="/assets" class="btn back-btn" data-back' in page


# --- 직원 빠른 등록 팝업 --------------------------------------------------------

def test_지급_폼에_팝업과_여는_버튼이_있다(admin_client, asset, db):
    page = admin_client.get(f"/assets/{asset.id}").text
    assert "data-open-employee-modal" in page
    assert 'id="employee-modal"' in page


def test_지급_화면에도_팝업이_있다(admin_client, asset):
    page = admin_client.get("/assignments/new").text
    assert "data-open-employee-modal" in page
    assert 'id="employee-modal"' in page


def test_팝업이_없을_때도_직원_등록_화면으로_갈_수_있다(admin_client, asset):
    """스크립트가 꺼져 있으면 평범한 링크로 남아야 한다."""
    page = admin_client.get(f"/assets/{asset.id}").text
    assert 'href="/employees/new" data-open-employee-modal' in page


def test_부서_자동완성_목록이_채워진다(admin_client, db, asset):
    db.add_all([
        Employee(emp_no="E1", name="가", department="개발팀"),
        Employee(emp_no="E2", name="나", department="영업팀"),
    ])
    db.commit()

    page = admin_client.get(f"/assets/{asset.id}").text
    assert 'id="known-departments"' in page
    assert '<option value="개발팀">' in page
    assert '<option value="영업팀">' in page


def test_팝업으로_직원을_등록한다(admin_client, db):
    response = admin_client.post(
        "/employees/quick",
        data={"emp_no": "E900", "name": "신규직원", "department": "개발팀", "status": "ACTIVE"},
    )
    assert response.status_code == 200

    body = response.json()
    assert body["ok"] is True
    assert body["label"] == "신규직원 (E900 · 개발팀)"
    assert "E900" in body["search"] and "개발팀" in body["search"]

    employee = db.scalar(select(Employee).where(Employee.emp_no == "E900"))
    assert employee is not None
    assert employee.status == "ACTIVE"
    assert body["id"] == employee.id


def test_부서가_없으면_라벨에서_생략한다(admin_client):
    response = admin_client.post(
        "/employees/quick", data={"emp_no": "E901", "name": "무소속", "status": "ACTIVE"}
    )
    assert response.json()["label"] == "무소속 (E901)"


def test_사번이_중복이면_거부한다(admin_client, db, employee):
    response = admin_client.post(
        "/employees/quick", data={"emp_no": employee.emp_no, "name": "다른사람", "status": "ACTIVE"}
    )
    assert response.status_code == 400
    body = response.json()
    assert body["ok"] is False
    assert "이미 등록" in body["error"]


@pytest.mark.parametrize(
    "data,message",
    [
        ({"emp_no": "", "name": "이름만"}, "사번"),
        ({"emp_no": "E902", "name": "  "}, "이름"),
        ({"emp_no": "E903", "name": "홍길동", "email": "잘못된주소"}, "이메일"),
    ],
)
def test_잘못된_입력은_사유와_함께_거부한다(admin_client, db, data, message):
    payload = {"status": "ACTIVE"}
    payload.update(data)
    response = admin_client.post("/employees/quick", data=payload)

    assert response.status_code == 400
    assert message in response.json()["error"]
    assert db.scalar(select(Employee)) is None


def test_일반_사용자는_팝업으로_등록할_수_없다(viewer_client):
    response = viewer_client.post(
        "/employees/quick", data={"emp_no": "E999", "name": "몰래등록", "status": "ACTIVE"}
    )
    assert response.status_code == 403


def test_로그인하지_않으면_등록할_수_없다(client):
    response = client.post(
        "/employees/quick", data={"emp_no": "E998", "name": "비로그인", "status": "ACTIVE"},
        follow_redirects=False,
    )
    assert response.status_code in (303, 401, 403)


def test_등록한_직원에게_바로_지급할_수_있다(admin_client, db, asset):
    """팝업 등록 → 지급 처리까지 실제로 이어지는지."""
    created = admin_client.post(
        "/employees/quick",
        data={"emp_no": "E950", "name": "바로지급", "department": "개발팀", "status": "ACTIVE"},
    ).json()

    response = admin_client.post(
        "/assignments/new",
        data={"asset_id": asset.id, "employee_id": created["id"]},
        follow_redirects=False,
    )
    assert response.status_code == 303

    db.expire_all()
    updated = db.get(Asset, asset.id)
    assert updated.status == "IN_USE"
    assert updated.holder.name == "바로지급"


def test_팝업_스크립트가_서빙된다(admin_client):
    response = admin_client.get("/static/js/quick-employee.js")
    assert response.status_code == 200
    assert "/employees/quick" in response.text


def test_화면_제목에_HTML_이_섞이지_않는다(admin_client, db, asset):
    """팝업을 제목 블록 안에 넣는 실수를 하면, 브라우저 탭 제목에 HTML 이 새어 나온다."""
    import re

    for path in (f"/assets/{asset.id}", "/assignments/new"):
        html = admin_client.get(path).text
        title = re.search(r"<title>(.*?)</title>", html, re.S).group(1)
        assert "<" not in title, f"{path}: {title[:60]}"


def test_빠른_등록_팝업은_화면에_하나만_있다(admin_client, db, asset):
    """두 번 그려지면 자바스크립트가 엉뚱한 쪽을 붙잡는다."""
    for path in (f"/assets/{asset.id}", "/assignments/new"):
        html = admin_client.get(path).text
        assert html.count('id="employee-modal"') == 1, path
