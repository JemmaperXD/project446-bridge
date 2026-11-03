@echo off
chcp 65001 >nul
rem ============================================================
rem  Project 446 — проверка обновлений моста.
rem
rem  Спрашивает GitHub, есть ли релиз новее вашего.
rem  Ничего не скачивает и не устанавливает.
rem ============================================================
setlocal EnableExtensions

set "CHECK=%~dp0check_updates.ps1"
if not exist "%CHECK%" (
    echo.
    echo  [project446] ОШИБКА: рядом нет check_updates.ps1.
    echo  [project446] Распакуйте архив ЦЕЛИКОМ, не по одному файлу.
    echo.
    pause
    exit /b 1
)

set "STATE="
set "CUR=?"
set "LAT=?"

for /f "usebackq tokens=1,2,3 delims= " %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%CHECK%" -Force`) do (
    set "STATE=%%a"
    set "CUR=%%b"
    set "LAT=%%c"
)

if "%STATE%"=="UPDATE" (
    echo.
    echo  ============================================================
    echo   У вас версия:    %CUR%
    echo   Доступна новее:  %LAT%
    echo  ============================================================
    echo.
    echo  Скачать: https://github.com/JemmaperXD/project446-bridge/releases/latest
    echo.
    echo  Как обновить:
    echo    1. Скачайте новый Project446-Windows.zip
    echo    2. Распакуйте его в ту же папку с заменой файлов
    echo       ^(bridge.py, start_bridge.bat, python\ и остальные^)
    echo    3. Параметры запуска в Steam менять не нужно
    echo.
) else if "%STATE%"=="OK" (
    echo.
    echo  У вас последняя версия: %CUR%
    echo.
) else (
    echo.
    echo  Не удалось проверить обновления.
    echo  Проверьте интернет или откройте вручную:
    echo  https://github.com/JemmaperXD/project446-bridge/releases
    echo.
)

pause
exit /b 0
