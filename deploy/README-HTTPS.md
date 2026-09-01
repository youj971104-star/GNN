# 사내 도메인 + HTTPS 로 전환하기

처음에는 `http://<서버IP>:8000` 으로 쓰다가, 나중에 사내 도메인과 인증서가 준비되면
**애플리케이션 코드는 그대로 두고** 아래 절차만 밟으면 됩니다.

---

## 1. 도메인 준비

사내 DNS 에 이 서버를 가리키는 이름을 등록합니다.

```
itam.회사도메인.co.kr   →   192.168.0.50 (이 서버의 IP)
```

## 2. 인증서 파일 놓기

인증서 파일 두 개를 `deploy/certs/` 폴더에 넣습니다.

```
deploy/certs/fullchain.pem    인증서 + 중간 인증서
deploy/certs/privkey.pem      개인키
```

* **사내 인증기관(사설 CA)** 발급분이라면 받은 파일을 위 이름으로 복사하면 됩니다.
* **Let's Encrypt** 를 쓴다면 `/etc/letsencrypt/live/<도메인>/` 아래 같은 이름의 파일을 복사합니다.
* 우선 테스트만 해보려면 자체 서명 인증서로도 동작합니다
  (브라우저 경고가 뜹니다).

  ```bash
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout deploy/certs/privkey.pem \
    -out deploy/certs/fullchain.pem \
    -subj "/CN=itam.회사도메인.co.kr"
  ```

> `deploy/certs/` 안의 인증서 파일은 git 에 올라가지 않도록 제외되어 있습니다.

## 3. 도메인 이름 바꾸기

`deploy/nginx.conf` 에서 `server_name` 두 곳을 실제 도메인으로 바꿉니다.

```nginx
server_name itam.회사도메인.co.kr;
```

## 4. 세션 쿠키를 HTTPS 전용으로

`.env` 파일에서 아래 값을 `1` 로 바꿉니다.
로그인 세션 쿠키가 HTTPS 로만 전송되어 더 안전해집니다.

```
ITAM_HTTPS_ONLY=1
```

## 5. 실행

```bash
docker compose --profile https up -d
```

이제 `https://itam.회사도메인.co.kr` 로 접속합니다.
80 번 포트로 들어온 요청은 자동으로 HTTPS 로 넘어갑니다.

## 6. (선택) 직접 포트 접속 막기

Nginx 를 거치도록 강제하려면, `docker-compose.yml` 의 `app` 서비스에서
`ports` 항목을 지우거나 서버 안에서만 열리도록 바꿉니다.

```yaml
    ports:
      - "127.0.0.1:${ITAM_PUBLIC_PORT:-8000}:8000"
```

---

## 되돌리기

HTTPS 를 끄고 원래대로 돌아가려면:

```bash
docker compose --profile https down
# .env 에서 ITAM_HTTPS_ONLY=0 으로 되돌린 뒤
./deploy.sh start
```

## 자주 겪는 문제

| 증상 | 원인과 해결 |
| --- | --- |
| 로그인해도 계속 로그인 화면으로 돌아온다 | `ITAM_HTTPS_ONLY=1` 인데 HTTP 로 접속하고 있는 경우입니다. HTTPS 주소로 접속하거나 값을 `0` 으로 되돌리세요. |
| Nginx 가 뜨자마자 죽는다 | 인증서 경로/파일명이 맞지 않는 경우가 대부분입니다. `docker compose logs nginx` 로 확인하세요. |
| 엑셀 업로드 시 413 오류 | 파일이 `client_max_body_size` 보다 큽니다. `deploy/nginx.conf` 값과 `.env` 의 `ITAM_MAX_UPLOAD_BYTES` 를 함께 올리세요. |
