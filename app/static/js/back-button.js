/*
 * 상단 '뒤로' 버튼.
 *
 * 같은 사이트 안에서 이동해 온 경우에는 브라우저 기록으로 돌아간다.
 * 그래야 목록에서 걸어둔 검색 조건과 페이지 번호가 그대로 유지된다.
 *
 * 기록이 없거나(주소를 직접 입력, QR 로 바로 진입) 다른 사이트에서 온 경우에는
 * 버튼의 href 에 적힌 상위 화면으로 간다. 자바스크립트가 꺼져 있어도
 * 평범한 링크로 동작하므로 항상 쓸 수 있다.
 */
(function () {
  "use strict";

  function cameFromSameSite() {
    if (!document.referrer) return false;
    try {
      return new URL(document.referrer).origin === window.location.origin;
    } catch (e) {
      return false;
    }
  }

  function init() {
    var button = document.querySelector("[data-back]");
    if (!button) return;

    button.addEventListener("click", function (event) {
      // 새 탭으로 열려는 조작은 건드리지 않는다
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;

      if (cameFromSameSite() && window.history.length > 1) {
        event.preventDefault();
        window.history.back();
      }
      // 그 밖의 경우는 href 로 그냥 이동한다
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
