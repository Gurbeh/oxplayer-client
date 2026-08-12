@echo off
setlocal
if not defined GIT_BASH if exist "%ProgramFiles%\Git\bin\bash.exe" set "GIT_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined GIT_BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "GIT_BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined GIT_BASH (
  echo error: Git Bash not found. Install Git for Windows or set GIT_BASH.
  exit /b 1
)
"%GIT_BASH%" "%~dp0scripts\release-client.sh" %*
