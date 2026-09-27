@echo off
setlocal
cd /d "%~dp0"
call "%~dp0_zig.cmd" || exit /b 1
"%ZIG%" build check %*
exit /b %errorlevel%
