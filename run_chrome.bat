@echo off
setlocal EnableExtensions

cd /d "%~dp0"

set "BACKEND_PORT=8000"
set "BACKEND_URL=http://127.0.0.1:%BACKEND_PORT%"
set "HEALTH_URL=%BACKEND_URL%/health"

echo [1/4] Project: %CD%

where python >nul 2>nul
if errorlevel 1 (
  echo ERROR: python was not found in PATH.
  pause
  exit /b 1
)

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: flutter was not found in PATH.
  pause
  exit /b 1
)

echo [2/4] Checking backend: %HEALTH_URL%
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $r = Invoke-RestMethod -Uri '%HEALTH_URL%' -TimeoutSec 2; if ($r.ok -eq $true) { exit 0 } } catch {}; exit 1"

if errorlevel 1 (
  echo Backend is not running. Starting FastAPI backend in a new window...
  if not exist "%~dp0.appdata" mkdir "%~dp0.appdata"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'python' -ArgumentList @('-m','uvicorn','backend.main:app','--host','127.0.0.1','--port','%BACKEND_PORT%','--reload') -WorkingDirectory '%~dp0' -WindowStyle Minimized -RedirectStandardOutput '%~dp0.appdata\backend-uvicorn.out.log' -RedirectStandardError '%~dp0.appdata\backend-uvicorn.err.log'"

  echo Waiting for backend health check...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ok=$false; for($i=0; $i -lt 30; $i++){ try { $r=Invoke-RestMethod -Uri '%HEALTH_URL%' -TimeoutSec 2; if($r.ok -eq $true){ $ok=$true; break } } catch {}; Start-Sleep -Seconds 1 }; if($ok){ exit 0 } else { exit 1 }"
  if errorlevel 1 (
    echo ERROR: backend failed to start. Keep the backend window open and check its error message.
    echo Backend stdout: %~dp0.appdata\backend-uvicorn.out.log
    echo Backend stderr: %~dp0.appdata\backend-uvicorn.err.log
    pause
    exit /b 1
  )
)

echo [3/4] Backend ready.

if /I "%~1"=="--check" (
  echo Check finished. Chrome was not started.
  exit /b 0
)

echo [4/4] Starting Flutter Chrome app...
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=%BACKEND_URL%

pause
