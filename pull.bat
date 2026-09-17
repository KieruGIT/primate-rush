@echo off
REM Double-click to bring this checkout up to date with GitHub.
REM Godot notices the changed files on its own when you click back into it.
cd /d "%~dp0"
echo Pulling latest changes...
git pull --ff-only
if errorlevel 1 (
  echo.
  echo Pull failed. Usually that means you have local edits that clash.
  echo Run "git status" to see them.
)
echo.
git log --oneline -3
echo.
pause
