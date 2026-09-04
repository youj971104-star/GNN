@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

echo.
echo   ================================================
echo    IT 자산관리 시스템 - 내 컴퓨터에서 실행하기
echo   ================================================
echo.

REM ── 1) 파이썬 찾기 ────────────────────────────────
set "PY="
py -3 --version >nul 2>&1
if not errorlevel 1 set "PY=py -3"
if defined PY goto :python_ok

python --version >nul 2>&1
if not errorlevel 1 set "PY=python"
if defined PY goto :python_ok

echo   [!] 파이썬이 설치되어 있지 않습니다.
echo.
echo       1. 잠시 후 열리는 페이지에서 "Download Python" 을 눌러 설치하세요.
echo       2. 설치 화면 맨 아래 "Add python.exe to PATH" 를 반드시 체크하세요.
echo       3. 설치가 끝나면 이 파일을 다시 실행하세요.
echo.
pause
start "" https://www.python.org/downloads/
exit /b 1

:python_ok
for /f "tokens=*" %%v in ('%PY% --version 2^>^&1') do echo   [1/4] 파이썬 확인: %%v

REM ── 2) 실행 환경 준비 ─────────────────────────────
set "VENV_PY=.venv\Scripts\python.exe"
if exist "%VENV_PY%" goto :venv_ok

echo   [2/4] 실행 환경을 만드는 중입니다... (처음 한 번만, 1~2분 걸립니다)
%PY% -m venv .venv
if errorlevel 1 goto :error_venv

:venv_ok
echo   [2/4] 실행 환경 확인
echo   [3/4] 필요한 패키지를 확인하는 중입니다...
"%VENV_PY%" -m pip install --quiet --upgrade pip
"%VENV_PY%" -m pip install --quiet -r requirements.txt
if errorlevel 1 goto :error_pip

REM ── 3) 로그인 세션 키 (없으면 만들어 두고 계속 재사용) ──
if exist ".local-secret" goto :secret_ok
"%VENV_PY%" -c "import secrets; open('.local-secret','w').write(secrets.token_hex(32)+chr(10))"
:secret_ok
set /p ITAM_SECRET_KEY=<.local-secret

set "ITAM_RELOAD=0"

REM 포트는 첫 번째 인자로 바꿀 수 있다.  예)  start-windows.bat 8001
set "ITAM_PORT=8000"
if not "%~1"=="" set "ITAM_PORT=%~1"

REM 이미 다른 프로그램이 그 포트를 쓰고 있으면 미리 알려 준다.
"%VENV_PY%" -c "import os,socket; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(('0.0.0.0',int(os.environ['ITAM_PORT']))); s.close()" >nul 2>&1
if not errorlevel 1 goto :port_ok
echo.
echo   [!] %ITAM_PORT% 번 포트를 이미 다른 프로그램이 쓰고 있습니다.
echo.
echo       이 프로그램이 이미 실행 중일 수도 있습니다.
echo       먼저 http://localhost:%ITAM_PORT% 로 접속해 보세요.
echo.
echo       다른 포트로 실행하려면 명령 프롬프트에서:  start-windows.bat 8001
echo.
pause
exit /b 1
:port_ok

REM ── 4) 처음 실행이면 샘플 데이터를 넣을지 물어본다 ──
if exist "data\itam.db" goto :run
echo.
set "SEED="
set /p SEED="  처음 실행이군요. 둘러보기 좋게 샘플 데이터를 넣을까요? (Y/N) "
if /i "%SEED%"=="Y" "%VENV_PY%" seed_demo.py

:run
echo.
echo   [4/4] 서버를 시작합니다.
echo.
echo   ------------------------------------------------
echo    브라우저에서 아래 주소로 접속하세요
echo.
echo        http://localhost:%ITAM_PORT%
echo.
echo    최초 관리자 계정   아이디: admin   비밀번호: admin1234
echo.
echo    종료하려면 이 창에서 Ctrl+C 를 누르거나 창을 닫으세요.
echo   ------------------------------------------------
echo.

start "" http://localhost:%ITAM_PORT%
"%VENV_PY%" run.py
goto :end

:error_venv
echo.
echo   [!] 실행 환경을 만들지 못했습니다.
echo       파이썬을 다시 설치하면서 "Add python.exe to PATH" 를 체크했는지 확인해 주세요.
pause
exit /b 1

:error_pip
echo.
echo   [!] 패키지 설치에 실패했습니다.
echo       인터넷 연결을 확인하시고, 사내망이라면 프록시 설정이 필요할 수 있습니다.
pause
exit /b 1

:end
echo.
echo   서버가 종료되었습니다.
pause
