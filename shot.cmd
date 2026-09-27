@echo off
setlocal
cd /d "%~dp0"
call "%~dp0build.cmd" --prefix zig-out-shot || exit /b 1
"zig-out-shot\bin\freespace-survivors.exe" --shot %*
exit /b %errorlevel%
