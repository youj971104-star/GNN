/*
 * 화면 여기저기서 쓰는 작은 동작들.
 *
 * 예전에는 onclick="window.print()" 처럼 HTML 안에 자바스크립트를 적어 두었다.
 * 그렇게 두면 브라우저에 '인라인 스크립트를 실행하지 말라'(CSP)고 지시할 수 없고,
 * 값이 잘못 섞였을 때 남의 코드가 실행될 여지가 남는다. 전부 이 파일로 옮겼다.
 */
(function () {
  "use strict";

  /* 인쇄 버튼 */
  function bindPrint() {
    document.querySelectorAll("[data-print]").forEach(function (button) {
      button.addEventListener("click", function () { window.print(); });
    });
  }

  /* 라벨 크기 고르기 - 고른 값을 body 에 적어 두면 CSS 가 칸 수를 바꾼다 */
  function bindLabelSize() {
    var select = document.querySelector("[data-label-size]");
    if (!select) return;
    select.addEventListener("change", function () {
      document.body.dataset.label = select.value;
    });
  }

  /* 복구 코드 복사 */
  function bindCopyCodes() {
    var button = document.querySelector("[data-copy-codes]");
    if (!button) return;

    button.addEventListener("click", function () {
      var text = Array.prototype.map.call(
        document.querySelectorAll("#codes .recovery-code"),
        function (el) { return el.textContent.trim(); }
      ).join("\n");

      function done() {
        var original = button.textContent;
        button.textContent = "복사했습니다";
        setTimeout(function () { button.textContent = original; }, 1500);
      }

      function fallback() {
        var area = document.createElement("textarea");
        area.value = text;
        area.style.position = "fixed";
        area.style.opacity = "0";
        document.body.appendChild(area);
        area.select();
        try {
          document.execCommand("copy");
          done();
        } catch (e) {
          window.alert("복사하지 못했습니다. 직접 선택해 복사해 주세요.");
        }
        document.body.removeChild(area);
      }

      // navigator.clipboard 는 HTTPS 에서만 동작하므로 안 될 때를 대비해 예전 방식도 남긴다
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(done).catch(fallback);
      } else {
        fallback();
      }
    });
  }

  /* 목록에서 줄 아무 곳이나 눌러도 상세로 간다.
     줄 안의 링크·버튼을 누르거나 글자를 고르는 중이면 건드리지 않는다.
     Ctrl(⌘)·가운데 단추로 누르면 새 탭으로 연다. */
  function bindRowLinks() {
    document.addEventListener("click", function (event) {
      var row = event.target.closest && event.target.closest("tr[data-href]");
      if (!row) return;
      if (event.target.closest("a, button, input, select, textarea, label")) return;
      if (window.getSelection && String(window.getSelection())) return;

      var href = row.getAttribute("data-href");
      if (event.ctrlKey || event.metaKey) {
        window.open(href, "_blank");
      } else {
        window.location.href = href;
      }
    });
    document.addEventListener("auxclick", function (event) {
      var row = event.target.closest && event.target.closest("tr[data-href]");
      if (row && event.button === 1 && !event.target.closest("a")) {
        window.open(row.getAttribute("data-href"), "_blank");
      }
    });
  }

  /* 화면 밝기: 자동 → 다크 → 라이트 → 자동.
     고른 값은 쿠키에 1년 동안 남겨, 다음에 열 때 서버가 처음부터 그 밝기로 그린다. */
  var THEME_ORDER = ["auto", "dark", "light"];
  var THEME_LABEL = { auto: "자동", dark: "다크", light: "라이트" };

  function bindThemeToggle() {
    var buttons = document.querySelectorAll("[data-theme-toggle]");
    Array.prototype.forEach.call(buttons, function (button) {
      button.hidden = false;
      button.addEventListener("click", function () {
        var root = document.documentElement;
        var now = THEME_ORDER.indexOf(root.getAttribute("data-theme"));
        var next = THEME_ORDER[(now + 1) % THEME_ORDER.length];

        root.setAttribute("data-theme", next);
        Array.prototype.forEach.call(document.querySelectorAll("[data-theme-label]"), function (label) {
          label.textContent = THEME_LABEL[next];
        });
        document.cookie = "theme=" + next + "; path=/; max-age=31536000; samesite=lax" +
          (location.protocol === "https:" ? "; secure" : "");
      });
    });
  }

  /* 휴대폰 메뉴 열고 닫기. 자바스크립트가 없으면 #sidebar 주소(:target)로 열린다. */
  function bindNavDrawer() {
    var body = document.body;
    var openers = document.querySelectorAll("[data-nav-open]");

    function setOpen(open) {
      body.classList.toggle("nav-open", open);
      Array.prototype.forEach.call(openers, function (el) {
        el.setAttribute("aria-expanded", open ? "true" : "false");
      });
      // 열면 닫기 단추로 초점을 옮긴다 (검색칸에 두면 폰 자판이 바로 올라와 가린다)
      if (open) {
        var close = document.querySelector("#sidebar .nav-close");
        if (close) close.focus({ preventScroll: true });
      }
    }

    Array.prototype.forEach.call(openers, function (el) {
      el.addEventListener("click", function (event) { event.preventDefault(); setOpen(true); });
    });
    Array.prototype.forEach.call(document.querySelectorAll("[data-nav-close]"), function (el) {
      el.addEventListener("click", function (event) { event.preventDefault(); setOpen(false); });
    });
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && body.classList.contains("nav-open")) setOpen(false);
    });
  }

  /* 키보드 / 를 누르면 어디서든 검색칸으로 */
  function bindSearchShortcut() {
    var input = document.querySelector("[data-global-search]");
    if (!input) return;
    document.addEventListener("keydown", function (event) {
      if (event.key !== "/" || event.ctrlKey || event.metaKey || event.altKey) return;
      var tag = (document.activeElement && document.activeElement.tagName) || "";
      if (/^(INPUT|TEXTAREA|SELECT)$/.test(tag) || document.activeElement.isContentEditable) return;
      if (input.offsetParent === null) return;          // 휴대폰처럼 검색칸이 숨어 있으면 그대로
      event.preventDefault();
      input.focus();
      input.select();
    });
  }

  /* 고르기만 해도 바로 검색 (검색어 칸은 Enter 나 검색 버튼으로) */
  function bindAutoSubmit() {
    Array.prototype.forEach.call(document.querySelectorAll("form[data-auto-submit]"), function (form) {
      form.addEventListener("change", function (event) {
        var target = event.target;
        if (target.matches("select, input[type=checkbox], input[type=radio]")) {
          if (form.requestSubmit) form.requestSubmit(); else form.submit();
        }
      });
    });
  }

  /* 휴대폰에서 상태 탭이 옆으로 넘치면, 지금 고른 탭이 보이도록 밀어 둔다 */
  function revealActiveTab() {
    Array.prototype.forEach.call(document.querySelectorAll(".status-tabs"), function (tabs) {
      var current = tabs.querySelector("a.active");
      if (current && tabs.scrollWidth > tabs.clientWidth) {
        tabs.scrollLeft = current.offsetLeft - (tabs.clientWidth - current.offsetWidth) / 2;
      }
    });
  }

  /* 안내 문구 닫기 */
  function bindDismiss() {
    Array.prototype.forEach.call(document.querySelectorAll("[data-dismiss]"), function (button) {
      button.hidden = false;
      button.addEventListener("click", function () {
        var box = button.closest(".alert");
        if (box) box.remove();
      });
    });
  }

  function init() {
    bindThemeToggle();
    bindNavDrawer();
    bindSearchShortcut();
    bindAutoSubmit();
    bindDismiss();
    revealActiveTab();
    bindRowLinks();
    bindPrint();
    bindLabelSize();
    bindCopyCodes();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
