/*
 * 항목이 많은 드롭다운 위에 검색칸을 붙인다.
 *
 * <select data-searchable="직원 이름 검색"> 라고 적어 두면 된다.
 * 각 <option> 의 data-search 속성에 적힌 글자로도 찾는다 (사번, 부서 등).
 *
 * 원래 <select> 를 그대로 쓰므로 키보드 조작, 모바일 선택기, 폼 전송이 모두
 * 평소처럼 동작한다. 이 스크립트가 실행되지 않아도 드롭다운은 그대로 쓸 수 있다.
 */
(function () {
  "use strict";

  function textOf(option) {
    return ((option.dataset.search || "") + " " + option.textContent).toLowerCase();
  }

  function setup(select) {
    if (select.dataset.searchableReady === "1") return;
    select.dataset.searchableReady = "1";

    var options = Array.prototype.slice.call(select.options);
    // 값이 없는 첫 항목("직원을 선택하세요")은 안내문이므로 걸러내지 않는다
    var realOptions = options.filter(function (o) { return o.value !== ""; });
    if (realOptions.length < 8) return;   // 몇 개 안 되면 검색칸이 오히려 번거롭다

    var box = document.createElement("div");
    box.className = "select-search";

    var input = document.createElement("input");
    input.type = "text";
    input.className = "select-search-input";
    input.placeholder = select.dataset.searchable || "검색";
    input.autocomplete = "off";
    input.setAttribute("aria-label", input.placeholder);

    var count = document.createElement("span");
    count.className = "select-search-count";

    box.appendChild(input);
    box.appendChild(count);
    select.parentNode.insertBefore(box, select);

    function showCount(shown) {
      count.textContent = shown === realOptions.length ? "" : shown + "건";
    }

    function filter() {
      var query = input.value.trim().toLowerCase();
      var words = query.split(/\s+/).filter(Boolean);
      var shown = 0;
      var lastMatch = null;

      realOptions.forEach(function (option) {
        var haystack = textOf(option);
        var hit = words.every(function (word) { return haystack.indexOf(word) !== -1; });
        option.hidden = !hit;
        option.disabled = !hit;   // 숨김을 지원하지 않는 브라우저 대비
        if (hit) { shown += 1; lastMatch = option; }
      });

      showCount(shown);

      // 딱 하나만 남으면 바로 골라 준다
      if (query && shown === 1 && lastMatch) {
        select.value = lastMatch.value;
        select.dispatchEvent(new Event("change", { bubbles: true }));
        return;
      }

      // 고른 항목이 검색에 걸러져 안 보이게 됐다면 선택을 비운다.
      // 그대로 두면 화면에는 안 보이는 값이 선택된 채로 전송되어 헷갈린다.
      var current = select.selectedOptions[0];
      if (current && current.hidden) {
        select.selectedIndex = 0;
        select.dispatchEvent(new Event("change", { bubbles: true }));
      }
    }

    input.addEventListener("input", filter);

    // 검색칸에서 Enter 를 눌러도 폼이 바로 전송되지 않게 한다 (실수 방지)
    input.addEventListener("keydown", function (event) {
      if (event.key === "Enter") {
        event.preventDefault();
        select.focus();
      }
    });

    showCount(realOptions.length);
  }

  function init() {
    document.querySelectorAll("select[data-searchable]").forEach(setup);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
