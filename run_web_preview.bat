@echo off
setlocal EnableExtensions

cd /d "%~dp0"

set "BACKEND_PORT=8000"
set "BACKEND_URL=http://127.0.0.1:%BACKEND_PORT%"
set "HEALTH_URL=%BACKEND_URL%/health"
set "WEB_PORT=5353"
set "WEB_URL=http://127.0.0.1:%WEB_PORT%/"

echo [1/5] Project: %CD%

where python >nul 2>nul
if errorlevel 1 (
  echo ERROR: python was not found in PATH.
  exit /b 1
)

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: flutter was not found in PATH.
  exit /b 1
)

echo [2/5] Checking backend: %HEALTH_URL%
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $r = Invoke-RestMethod -Uri '%HEALTH_URL%' -TimeoutSec 2; if ($r.ok -eq $true) { exit 0 } } catch {}; exit 1"

if errorlevel 1 (
  echo Backend is not running. Starting FastAPI backend in a new window...
  if not exist "%~dp0.appdata" mkdir "%~dp0.appdata"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'python' -ArgumentList @('-m','uvicorn','backend.main:app','--host','127.0.0.1','--port','%BACKEND_PORT%') -WorkingDirectory '%~dp0' -WindowStyle Minimized -RedirectStandardOutput '%~dp0.appdata\backend-uvicorn.out.log' -RedirectStandardError '%~dp0.appdata\backend-uvicorn.err.log'"

  echo Waiting for backend health check...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ok=$false; for($i=0; $i -lt 30; $i++){ try { $r=Invoke-RestMethod -Uri '%HEALTH_URL%' -TimeoutSec 2; if($r.ok -eq $true){ $ok=$true; break } } catch {}; Start-Sleep -Seconds 1 }; if($ok){ exit 0 } else { exit 1 }"
  if errorlevel 1 (
    echo ERROR: backend failed to start. Check .appdata\backend-uvicorn.err.log.
    exit /b 1
  )
)

echo [3/5] Backend ready.

if /I "%~1"=="--check" (
  echo Check finished. The Web bundle was not rebuilt.
  exit /b 0
)

echo [4/5] Building the latest Flutter Web bundle...
call flutter pub get
if errorlevel 1 (
  echo ERROR: flutter pub get failed.
  exit /b 1
)

call flutter build web --release --no-wasm-dry-run --dart-define=API_BASE_URL=%BACKEND_URL%
if errorlevel 1 (
  echo ERROR: Flutter Web build failed.
  exit /b 1
)

echo [5/5] Starting static Web preview: %WEB_URL%
if not exist "%~dp0.appdata" mkdir "%~dp0.appdata"

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $r = Invoke-WebRequest -UseBasicParsing -Uri '%WEB_URL%' -TimeoutSec 2; if ($r.StatusCode -eq 200 -and $r.Content -match 'flutter_bootstrap.js') { exit 0 } } catch {}; exit 1"
if errorlevel 1 (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'python' -ArgumentList @('-m','http.server','%WEB_PORT%','--bind','127.0.0.1','--directory','%~dp0build\web') -WorkingDirectory '%~dp0' -WindowStyle Minimized -RedirectStandardOutput '%~dp0.appdata\web-preview.out.log' -RedirectStandardError '%~dp0.appdata\web-preview.err.log'"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ok=$false; for($i=0; $i -lt 15; $i++){ try { $r=Invoke-WebRequest -UseBasicParsing -Uri '%WEB_URL%' -TimeoutSec 2; if($r.StatusCode -eq 200 -and $r.Content -match 'flutter_bootstrap.js'){ $ok=$true; break } } catch {}; Start-Sleep -Milliseconds 300 }; if($ok){ exit 0 } else { exit 1 }"
  if errorlevel 1 (
    echo ERROR: Web preview failed to start. Check .appdata\web-preview.err.log.
    exit /b 1
  )
)

echo Web preview ready: %WEB_URL%
start "" "%WEB_URL%"
exit /b 0
