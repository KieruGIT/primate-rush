@echo off
REM Leave this window open while Claude is working: it pulls every 30s, so
REM new commits land in Godot without you doing anything. Ctrl+C to stop.
cd /d "%~dp0"
:loop
git fetch --quiet origin
for /f %%i in ('git rev-list HEAD...origin/main --count 2^>nul') do set BEHIND=%%i
if not "%BEHIND%"=="0" (
  echo [%time%] New commits found, pulling...
  git pull --ff-only
  git log --oneline -1
)
timeout /t 30 /nobreak >nul
goto loop
