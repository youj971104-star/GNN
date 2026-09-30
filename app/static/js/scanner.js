/*
 * QR 스캔 화면.
 *
 * 카메라 화면을 일정 간격으로 들여다보며 QR 을 찾는다. 찾으면 서버에 물어
 * 자산 정보를 옆에 띄우고, 계속 다음 라벨을 기다린다. 화면이 넘어가지
 * 않으므로 여러 대를 이어서 확인할 수 있다.
 *
 * QR 해독은 브라우저에 있는 BarcodeDetector 를 먼저 쓴다. 없는 브라우저
 * (아이폰 사파리 등)에서는 함께 넣어 둔 jsQR 로 해독한다.
 *
 * 카메라는 HTTPS 에서만 열린다. http 로 들어오면 안내만 하고 직접 입력을 받는다.
 */
(function () {
  "use strict";

  var SCAN_INTERVAL_MS = 220;      // 초당 4~5회면 충분하고 배터리도 덜 쓴다
  var SAME_CODE_COOLDOWN_MS = 1500; // 같은 라벨을 계속 읽어 요청이 쏟아지는 것을 막는다

  var video, canvas, context, detector = null;
  var stream = null, timer = null, track = null;
  var lastCode = "", lastCodeAt = 0, torchOn = false;
  var history = [];   // 이번 화면에서 찍은 자산들

  function $(id) { return document.getElementById(id); }

  function showError(message) {
    var box = $("scan-error");
    box.textContent = message;
    box.hidden = !message;
  }

  function setState(message) {
    $("scan-state").textContent = message;
  }

  /* ── 카메라 ────────────────────────────────────────────── */

  function start() {
    showError("");
    setState("카메라를 여는 중...");

    var constraints = {
      audio: false,
      video: {
        facingMode: { ideal: "environment" },   // 폰은 뒷면 카메라
        width: { ideal: 1280 },
        height: { ideal: 720 },
      },
    };

    navigator.mediaDevices.getUserMedia(constraints)
      .then(function (media) {
        stream = media;
        track = media.getVideoTracks()[0] || null;
        video.srcObject = media;
        return video.play();
      })
      .then(function () {
        $("scan-placeholder").hidden = true;
        $("scan-start").hidden = true;
        $("scan-stop").hidden = false;
        setupTorch();
        setState("라벨을 화면 가운데에 맞춰 주세요.");
        timer = setInterval(tick, SCAN_INTERVAL_MS);
      })
      .catch(function (error) {
        var name = error && error.name;
        if (name === "NotAllowedError" || name === "SecurityError") {
          showError("카메라 사용이 허용되지 않았습니다. 주소창 왼쪽의 자물쇠에서 카메라를 허용해 주세요.");
        } else if (name === "NotFoundError" || name === "OverconstrainedError") {
          showError("쓸 수 있는 카메라를 찾지 못했습니다. 아래에서 자산번호를 직접 입력해 주세요.");
        } else {
          showError("카메라를 열지 못했습니다: " + (error && error.message ? error.message : name));
        }
        setState("카메라를 켤 수 없습니다.");
      });
  }

  function stop() {
    if (timer) { clearInterval(timer); timer = null; }
    if (stream) {
      stream.getTracks().forEach(function (t) { t.stop(); });
      stream = null;
      track = null;
    }
    video.srcObject = null;
    torchOn = false;
    $("scan-placeholder").hidden = false;
    $("scan-start").hidden = false;
    $("scan-stop").hidden = true;
    $("scan-torch").hidden = true;
    setState("멈췄습니다. 다시 켜려면 '카메라 켜기' 를 누르세요.");
  }

  /* 어두운 창고에서 라벨을 읽을 수 있게 (안드로이드 일부 기기만 지원) */
  function setupTorch() {
    var button = $("scan-torch");
    if (!track || typeof track.getCapabilities !== "function") return;

    var capabilities;
    try { capabilities = track.getCapabilities(); } catch (e) { return; }
    if (!capabilities || !capabilities.torch) return;

    button.hidden = false;
    button.onclick = function () {
      torchOn = !torchOn;
      track.applyConstraints({ advanced: [{ torch: torchOn }] })
        .then(function () { button.textContent = torchOn ? "불빛 끄기" : "불빛 켜기"; })
        .catch(function () { button.hidden = true; });
    };
  }

  /* ── QR 읽기 ───────────────────────────────────────────── */

  function tick() {
    if (!video.videoWidth || video.readyState < 2) return;

    if (detector) {
      detector.detect(video)
        .then(function (codes) {
          if (codes && codes.length) handleCode(codes[0].rawValue);
        })
        .catch(function () { detector = null; });   // 실패하면 jsQR 로 넘어간다
      return;
    }
    decodeWithJsQR();
  }

  var MAX_DECODE_EDGE = 800;   // 폰에서 1280 짜리를 통째로 훑으면 느리고 배터리를 먹는다

  function decodeWithJsQR() {
    if (typeof window.jsQR !== "function") return;

    // 긴 변을 800 으로 줄여서 읽는다. 라벨이 화면을 어느 정도 채우면 이 정도로 충분하다.
    var ratio = Math.min(1, MAX_DECODE_EDGE / Math.max(video.videoWidth, video.videoHeight));
    canvas.width = Math.round(video.videoWidth * ratio);
    canvas.height = Math.round(video.videoHeight * ratio);
    context.drawImage(video, 0, 0, canvas.width, canvas.height);

    var image = context.getImageData(0, 0, canvas.width, canvas.height);
    var found = window.jsQR(image.data, image.width, image.height, {
      inversionAttempts: "dontInvert",   // 라벨은 흰 바탕에 검은 QR 이다
    });
    if (found && found.data) handleCode(found.data);
  }

  function handleCode(text) {
    if (!text) return;

    var now = Date.now();
    if (text === lastCode && now - lastCodeAt < SAME_CODE_COOLDOWN_MS) return;
    lastCode = text;
    lastCodeAt = now;

    beep();
    lookup(text);
  }

  /* 찍혔다는 것을 소리로 알려 준다. 화면을 보지 않고 연달아 찍을 때 필요하다. */
  function beep() {
    try {
      var Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return;
      var ctx = new Ctx();
      var osc = ctx.createOscillator();
      var gain = ctx.createGain();
      osc.frequency.value = 880;
      gain.gain.value = 0.08;
      osc.connect(gain); gain.connect(ctx.destination);
      osc.start();
      setTimeout(function () { osc.stop(); ctx.close(); }, 90);
    } catch (e) { /* 소리는 못 내도 스캔은 계속된다 */ }
  }

  /* ── 서버에 물어보기 ───────────────────────────────────── */

  function lookup(code) {
    setState("찾는 중...");
    fetch("/scan/lookup?code=" + encodeURIComponent(code), {
      credentials: "same-origin",
      headers: { "X-Requested-With": "fetch" },
    })
      .then(function (response) {
        if (response.redirected || response.status === 401 || response.status === 403) {
          window.location.href = "/login?next=%2Fscan";
          return null;
        }
        return response.json();
      })
      .then(function (data) {
        if (!data) return;
        if (!data.ok) {
          renderMissing(data.error || "자산을 찾지 못했습니다.");
          setState("다음 라벨을 비춰 주세요.");
          return;
        }
        renderAsset(data);
        remember(data);
        setState("다음 라벨을 비춰 주세요.");
      })
      .catch(function () {
        renderMissing("서버에 연결하지 못했습니다. 잠시 후 다시 찍어 주세요.");
        setState("다음 라벨을 비춰 주세요.");
      });
  }

  /* ── 화면 그리기 ───────────────────────────────────────── */

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }

  /* 상태 색은 목록 화면과 같은 규칙을 쓴다 (.badge.IN_USE 등) */
  function statusClass(code) {
    return code ? "badge " + code : "badge";
  }

  function renderAsset(data) {
    var rows = [
      ["자산번호", data.asset_no],
      ["분류", data.category],
      ["모델", data.model],
      ["시리얼", data.serial_no],
      ["보관위치", data.location],
    ];

    var html = '<div class="scan-found">';
    html += '<div class="scan-found-head">';
    html += '<h3>' + escapeHtml(data.name) + '</h3>';
    html += '<span class="' + statusClass(data.status_code) + '">' + escapeHtml(data.status) + '</span>';
    html += '</div>';

    html += '<table class="scan-found-table"><tbody>';
    rows.forEach(function (row) {
      if (!row[1]) return;
      html += '<tr><th>' + escapeHtml(row[0]) + '</th><td>' + escapeHtml(row[1]) + '</td></tr>';
    });
    if (data.holder) {
      var who = data.holder.name + " (" + data.holder.emp_no + ")";
      if (data.holder.department) who += " · " + data.holder.department;
      html += '<tr><th>사용자</th><td>' + escapeHtml(who) + '</td></tr>';
      if (data.holder.since) {
        html += '<tr><th>지급일</th><td>' + escapeHtml(data.holder.since) + '</td></tr>';
      }
    } else {
      html += '<tr><th>사용자</th><td class="muted">지급되지 않음</td></tr>';
    }
    html += '</tbody></table>';

    html += '<div class="section-actions" style="margin-top:14px;">';
    html += '<a class="btn primary" href="' + escapeHtml(data.detail_url) + '">자산 상세 열기</a>';
    if (data.can_manage) {
      html += '<a class="btn" href="' + escapeHtml(data.action_url) + '">' +
              escapeHtml(data.action_label) + '</a>';
    }
    html += '</div></div>';

    $("scan-result").className = "";
    $("scan-result").innerHTML = html;
  }

  function renderMissing(message) {
    $("scan-result").className = "";
    $("scan-result").innerHTML = '<div class="alert warn" style="margin:0;">' +
      escapeHtml(message) + '</div>';
  }

  function remember(data) {
    var now = new Date();
    var time = ("0" + now.getHours()).slice(-2) + ":" + ("0" + now.getMinutes()).slice(-2) +
               ":" + ("0" + now.getSeconds()).slice(-2);

    history = history.filter(function (item) { return item.id !== data.id; });
    history.unshift({
      id: data.id, time: time, asset_no: data.asset_no, name: data.name,
      status: data.status, status_code: data.status_code,
      holder: data.holder ? data.holder.name : "",
      detail_url: data.detail_url,
    });

    var rows = history.map(function (item) {
      return '<tr>' +
        '<td class="mono">' + escapeHtml(item.time) + '</td>' +
        '<td class="mono">' + escapeHtml(item.asset_no) + '</td>' +
        '<td>' + escapeHtml(item.name) + '</td>' +
        '<td><span class="' + statusClass(item.status_code) + '">' + escapeHtml(item.status) + '</span></td>' +
        '<td>' + (item.holder ? escapeHtml(item.holder) : '<span class="muted">-</span>') + '</td>' +
        '<td><a href="' + escapeHtml(item.detail_url) + '">열기</a></td>' +
        '</tr>';
    }).join("");

    $("scan-history").innerHTML = rows;
    $("scan-count").textContent = history.length + "건";
  }

  /* ── 시작 ──────────────────────────────────────────────── */

  function init() {
    video = $("scan-video");
    if (!video) return;

    canvas = document.createElement("canvas");
    context = canvas.getContext("2d", { willReadFrequently: true });

    var manual = $("scan-manual");
    $("scan-manual-go").addEventListener("click", function () {
      var value = manual.value.trim();
      if (value) lookup(value);
    });
    manual.addEventListener("keydown", function (event) {
      if (event.key === "Enter") {
        event.preventDefault();
        $("scan-manual-go").click();
      }
    });

    // 카메라는 보안 연결(HTTPS)에서만 열린다
    var canUseCamera = window.isSecureContext &&
      navigator.mediaDevices && navigator.mediaDevices.getUserMedia;
    if (!canUseCamera) {
      $("scan-origin").textContent = window.location.origin;
      $("scan-insecure").hidden = false;
      $("scan-start").disabled = true;
      setState("자산번호를 직접 입력해 주세요.");
      return;
    }

    if ("BarcodeDetector" in window) {
      try {
        detector = new window.BarcodeDetector({ formats: ["qr_code"] });
      } catch (e) {
        detector = null;   // jsQR 로 대신한다
      }
    }

    $("scan-start").addEventListener("click", start);
    $("scan-stop").addEventListener("click", stop);

    // 화면을 떠나거나 다른 앱으로 넘어가면 카메라를 놓아 준다
    window.addEventListener("pagehide", stop);
    document.addEventListener("visibilitychange", function () {
      if (document.hidden && stream) stop();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
