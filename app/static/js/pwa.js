/*
 * 폰 홈 화면에 앱으로 설치하기.
 *
 * - 서비스 워커를 등록한다 (HTTPS 에서만 동작).
 * - 크롬·삼성 인터넷이 '설치할 수 있다'고 알려 주면 [앱 설치] 버튼을 보여 준다.
 *   아이폰 사파리는 이 신호가 없어서, 설치 안내 화면의 순서대로 직접 추가한다.
 */
(function () {
  "use strict";

  var secure = location.protocol === "https:" ||
    location.hostname === "localhost" || location.hostname === "127.0.0.1";

  if ("serviceWorker" in navigator && secure) {
    window.addEventListener("load", function () {
      navigator.serviceWorker.register("/sw.js", { scope: "/" }).catch(function () {});
    });
  }

  function installed() {
    return window.matchMedia("(display-mode: standalone)").matches ||
      window.navigator.standalone === true;
  }

  function each(selector, fn) {
    Array.prototype.forEach.call(document.querySelectorAll(selector), fn);
  }

  var deferred = null;

  /* 화면의 [data-install-state="ready manual"] 같은 부분 중 지금 상태에 맞는 것만 보인다.
       installed 이미 설치함 / ready 버튼 한 번으로 설치 / manual 메뉴에서 직접 / insecure HTTPS 아님 */
  function showState(forced) {
    var state = forced || (installed() ? "installed" :
      (deferred ? "ready" : (secure ? "manual" : "insecure")));
    each("[data-install-state]", function (el) {
      el.hidden = el.getAttribute("data-install-state").split(" ").indexOf(state) < 0;
    });
  }

  window.addEventListener("beforeinstallprompt", function (event) {
    deferred = event;
    showState();
  });

  window.addEventListener("appinstalled", function () {
    deferred = null;
    showState("installed");
  });

  function init() {
    showState();
    each("[data-install-app]", function (button) {
      button.addEventListener("click", function () {
        if (!deferred) return;
        var prompt = deferred;
        deferred = null;
        prompt.prompt();
        prompt.userChoice.then(function (choice) {
          if (choice.outcome !== "accepted") deferred = null;
          showState();
        });
      });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
