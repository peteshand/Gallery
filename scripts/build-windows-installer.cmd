@echo off
setlocal
call "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat" -arch=amd64 -vcvars_ver=14.50 >nul
if errorlevel 1 exit /b %errorlevel%
set "PATH=%~dp0..\.tools\cargo\bin;%PATH%"
call npm.cmd run tauri:build -- --bundles nsis
exit /b %errorlevel%
