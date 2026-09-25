@echo off
setlocal
for %%i in ("%~dp0..") do set "GALLERY_ROOT=%%~fi"
call "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat" -arch=amd64 -vcvars_ver=14.50 >nul
if errorlevel 1 exit /b %errorlevel%
set "JAVA_HOME=%GALLERY_ROOT%\.tools\android-jdk\jdk-17.0.20.1+1"
set "ANDROID_HOME=%GALLERY_ROOT%\.tools\android-sdk"
set "NDK_HOME=%ANDROID_HOME%\ndk\28.2.13676358"
set "CARGO_HOME=%GALLERY_ROOT%\.tools\cargo"
set "RUSTUP_HOME=%GALLERY_ROOT%\.tools\rustup"
set "CARGO_TARGET_DIR=%GALLERY_ROOT%\.tools\target"
set "GRADLE_USER_HOME=%GALLERY_ROOT%\.tools\gradle"
set "CARGO_BUILD_JOBS=2"
set "CARGO_PROFILE_DEV_STRIP=debuginfo"
set "PATH=%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%CARGO_HOME%\bin;%PATH%"
call "%GALLERY_ROOT%\node_modules\.bin\tauri.cmd" android build --debug --apk -t aarch64 --ci
exit /b %errorlevel%
