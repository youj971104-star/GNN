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

  function init() {
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
