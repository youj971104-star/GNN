/*
 * 서비스 워커 - 폰에 설치한 앱이 인터넷이 끊겼을 때 하얀 화면 대신 안내 화면을 보여 준다.
 *
 * 자산·직원 화면은 저장해 두지 않는다. 화면마다 개인정보가 있고, 오래된 내용을
 * 최신인 것처럼 보여 주면 안 되기 때문이다. 미리 받아 두는 것은 안내 화면과
 * 그 화면이 쓰는 글꼴·색(style.css), 아이콘뿐이다.
 *
 * 이 파일을 고치면 폰이 다음에 앱을 열 때 새 버전으로 바꾼다.
 */
"use strict";

var CACHE = "itam-offline-v1";
var OFFLINE_URL = "/offline";
var PRECACHE = [OFFLINE_URL, "/static/css/style.css", "/static/icons/icon-192.png"];

self.addEventListener("install", function (event) {
  event.waitUntil(
    caches.open(CACHE).then(function (cache) {
      return cache.addAll(PRECACHE.map(function (url) {
        return new Request(url, { cache: "reload" });
      }));
    }).then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches.keys().then(function (names) {
      return Promise.all(names.filter(function (name) { return name !== CACHE; })
        .map(function (name) { return caches.delete(name); }));
    }).then(function () { return self.clients.claim(); })
  );
});

self.addEventListener("fetch", function (event) {
  var request = event.request;
  if (request.method !== "GET") return;          // 저장·지급 같은 전송은 손대지 않는다

  // 화면 이동: 언제나 서버에서 새로 받고, 연결이 없을 때만 안내 화면
  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request).catch(function () { return caches.match(OFFLINE_URL); })
    );
    return;
  }

  // 안내 화면이 쓰는 파일: 서버 것을 먼저, 연결이 없으면 받아 둔 것
  var url = new URL(request.url);
  if (url.origin === self.location.origin && PRECACHE.indexOf(url.pathname) > 0) {
    event.respondWith(
      fetch(request).catch(function () { return caches.match(url.pathname); })
    );
  }
});
