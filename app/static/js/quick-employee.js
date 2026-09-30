/*
 * 자산 지급 화면의 '직원 빠른 등록' 팝업.
 *
 * 지급하려는데 그 직원이 아직 명부에 없을 때, 화면을 벗어나지 않고 등록한다.
 * 등록이 끝나면 옆의 직원 드롭다운에 항목을 넣고 그대로 선택해 준다.
 *
 * 이 스크립트가 없으면 팝업 여는 버튼이 '직원 관리'로 가는 평범한 링크로 남는다.
 */
(function () {
  "use strict";

  var modal, errorBox, submitButton, lastFocused;

  function show(message) {
    errorBox.textContent = message;
    errorBox.hidden = false;
  }

  function clearError() {
    errorBox.hidden = true;
    errorBox.textContent = "";
  }

  function fields() {
    return {
      emp_no: document.getElementById("qe_emp_no"),
      name: document.getElementById("qe_name"),
      department: document.getElementById("qe_department"),
      position: document.getElementById("qe_position"),
      email: document.getElementById("qe_email"),
      phone: document.getElementById("qe_phone"),
    };
  }

  function openModal(event) {
    if (event) event.preventDefault();
    lastFocused = document.activeElement;
    clearError();
    modal.hidden = false;
    modal.setAttribute("aria-hidden", "false");
    document.body.style.overflow = "hidden";
    fields().emp_no.focus();
  }

  function closeModal() {
    modal.hidden = true;
    modal.setAttribute("aria-hidden", "true");
    document.body.style.overflow = "";
    if (lastFocused) lastFocused.focus();
  }

  function employeeSelect() {
    return document.getElementById("employee_id");
  }

  /* 새로 만든 직원을 드롭다운에 넣고 고른다.
     검색칸이 붙어 있을 수 있으므로 검색어도 비워 목록이 다시 다 보이게 한다. */
  function addAndSelect(data) {
    var select = employeeSelect();
    if (!select) return;

    var option = document.createElement("option");
    option.value = String(data.id);
    option.textContent = data.label;
    option.dataset.search = data.search || data.label;
    select.appendChild(option);
    select.value = option.value;

    var box = select.parentNode.querySelector(".select-search-input");
    if (box) {
      box.value = "";
      box.dispatchEvent(new Event("input", { bubbles: true }));
      select.value = option.value;   // 검색칸 초기화가 선택을 되돌릴 수 있어 다시 지정
    }
    select.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function submit() {
    clearError();
    var input = fields();

    if (!input.emp_no.value.trim()) {
      show("사번을 입력해 주세요.");
      input.emp_no.focus();
      return;
    }
    if (!input.name.value.trim()) {
      show("이름을 입력해 주세요.");
      input.name.focus();
      return;
    }

    var body = new FormData();
    Object.keys(input).forEach(function (key) {
      body.append(key, input[key].value.trim());
    });
    body.append("status", "ACTIVE");

    submitButton.disabled = true;
    submitButton.textContent = "등록 중...";

    fetch("/employees/quick", {
      method: "POST",
      body: body,
      credentials: "same-origin",
      headers: { "X-Requested-With": "fetch" },
    })
      .then(function (response) {
        // 로그인이 풀렸으면 로그인 화면으로 보낸다
        if (response.redirected || response.status === 401 || response.status === 403) {
          window.location.href = "/login";
          return null;
        }
        return response.json().catch(function () {
          throw new Error("서버 응답을 읽지 못했습니다.");
        });
      })
      .then(function (data) {
        if (!data) return;
        if (!data.ok) {
          show(data.error || "등록하지 못했습니다.");
          return;
        }
        addAndSelect(data);
        closeModal();
        Object.keys(input).forEach(function (key) { input[key].value = ""; });
      })
      .catch(function (error) {
        show(error.message || "등록 중 문제가 발생했습니다. 잠시 후 다시 시도해 주세요.");
      })
      .finally(function () {
        submitButton.disabled = false;
        submitButton.textContent = "등록하고 선택";
      });
  }

  function init() {
    modal = document.getElementById("employee-modal");
    var opener = document.querySelector("[data-open-employee-modal]");
    if (!modal || !opener) return;

    errorBox = document.getElementById("employee-modal-error");
    submitButton = document.getElementById("employee-modal-submit");

    opener.addEventListener("click", openModal);
    submitButton.addEventListener("click", submit);

    modal.querySelectorAll("[data-close-modal]").forEach(function (element) {
      element.addEventListener("click", closeModal);
    });

    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && !modal.hidden) closeModal();
    });

    // 팝업 안에서 Enter 를 누르면 바로 등록되게 한다
    modal.querySelectorAll("input").forEach(function (input) {
      input.addEventListener("keydown", function (event) {
        if (event.key === "Enter") {
          event.preventDefault();
          submit();
        }
      });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
