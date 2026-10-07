/*
 * 되돌릴 수 없는 작업(삭제 등) 앞에서 한 번 더 묻는다.
 *
 *   <form method="post" action="..." data-confirm="정말 지울까요?">
 *
 * 예전에는 onsubmit="return confirm('... {{ 자산번호 }} ...')" 처럼 썼는데,
 * 그러면 자산번호나 이름에 들어 있는 따옴표가 자바스크립트 문자열을 끊어
 * 데이터에 심어 둔 코드가 실행될 수 있었다. 값을 속성에만 담고 자바스크립트
 * 문자열로는 만들지 않는다.
 *
 * 이 스크립트가 없으면 확인 없이 바로 처리된다. 권한 검사는 서버에서 하므로
 * 안전에는 문제가 없다.
 */
(function () {
  "use strict";

  document.addEventListener("submit", function (event) {
    var form = event.target;
    if (!form || !form.matches || !form.matches("form[data-confirm]")) return;

    var message = form.getAttribute("data-confirm");
    if (message && !window.confirm(message)) {
      event.preventDefault();
    }
  });
})();
