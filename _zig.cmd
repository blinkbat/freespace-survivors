@echo off
set "ZIG=%~dp0..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe"
if not exist "%ZIG%" (echo Missing Zig toolchain: %ZIG% & exit /b 1)
