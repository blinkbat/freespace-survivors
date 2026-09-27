@echo off
setlocal
cd /d "%~dp0"
call "%~dp0build.cmd" || exit /b 1
"zig-out\bin\freespace-survivors.exe" %*
