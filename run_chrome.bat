@echo off
rem Compatibility alias. The canonical entry is run_web_preview.bat.
call "%~dp0run_web_preview.bat" %*
exit /b %ERRORLEVEL%
