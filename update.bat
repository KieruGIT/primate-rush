@echo off
REM Double-click to bring this checkout up to date with GitHub.
REM
REM Unlike pull.bat this does not give up when you have local edits: it
REM parks them in a git stash first, pulls, and tells you they are parked.
REM Nothing is ever deleted - "git stash list" shows what was set aside and
REM "git stash pop" puts it back.
cd /d "%~dp0"

echo Checking for local edits...
git diff --quiet
if errorlevel 1 goto stash
git diff --cached --quiet
if errorlevel 1 goto stash
goto pull

:stash
echo Local edits found. Parking them so the update can land.
git stash push -m "auto-parked by update.bat"
echo Parked. Run "git stash pop" later if you want them back.
echo.

:pull
echo Pulling latest changes...
git fetch origin
git pull --ff-only origin main
if errorlevel 1 (
  echo.
  echo ============================================================
  echo  Pull failed. Copy everything above and keep it for troubleshooting.
  echo  Do NOT run "reset --hard" - that is how work gets lost.
  echo ============================================================
  echo.
  pause
  exit /b 1
)

echo.
echo ============================================================
echo  Up to date. You are now on:
git log --oneline -1
echo.
echo  Now reopen Godot. First launch is slow - it re-imports.
echo ============================================================
echo.
pause
