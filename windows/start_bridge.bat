@echo off
chcp 65001 >nul
rem ============================================================
rem  Project 446 — запуск игры вместе с мостом (Windows)
rem
rem  Вставляется в Steam -> Свойства игры -> Параметры запуска:
rem      "C:\Project446\start_bridge.bat" %command%
rem
rem  Если мост уже слушает 127.0.0.1:443 — он переиспользуется.
rem  Иначе bridge.py запускается в фоне, окно ждёт порт и
rem  запускает игру (%*).
rem ============================================================
setlocal EnableExtensions
cd /d "%~dp0"
title Project 446

set "PORT=443"
set "BRIDGE=%~dp0bridge.py"
set "PY=%~dp0python\pythonw.exe"

if not exist "%PY%" (
    echo.
    echo  [project446] ОШИБКА: рядом нет папки python.
    echo  [project446] Распакуйте архив ЦЕЛИКОМ, не по одному файлу.
    echo.
    pause
    exit /b 1
)
if not exist "%BRIDGE%" (
    echo.
    echo  [project446] ОШИБКА: рядом нет bridge.py.
    echo  [project446] Распакуйте архив ЦЕЛИКОМ, не по одному файлу.
    echo.
    pause
    exit /b 1
)

findstr /I /C:"gc.project446.com" "%SystemRoot%\System32\drivers\etc\hosts" >nul 2>&1
if errorlevel 1 (
    echo.
    echo  ============================================================
    echo   ВНИМАНИЕ: в файле hosts нет записи gc.project446.com.
    echo   Запустите ОДИН РАЗ файл 1_SETUP.bat и согласитесь на UAC.
    echo   Без этой записи игра пойдёт мимо моста.
    echo  ============================================================
    echo.
)

netstat -ano | findstr /C:"127.0.0.1:%PORT%" | findstr /C:"LISTENING" >nul 2>&1
if not errorlevel 1 goto run_game

echo [project446] Запускаю мост на 127.0.0.1:%PORT% ...
start "project446-bridge" /min "%PY%" "%BRIDGE%" %PORT%

set /a WAIT=0
:wait_loop
netstat -ano | findstr /C:"127.0.0.1:%PORT%" | findstr /C:"LISTENING" >nul 2>&1
if not errorlevel 1 (
    echo [project446] Мост работает.
    goto run_game
)
set /a WAIT+=1
if %WAIT% GEQ 40 (
    echo.
    echo  [project446] Мост не поднялся за 16 секунд.
    echo  [project446] Откройте bridge.log рядом со скриптом.
    echo.
    goto run_game
)
ping -n 1 -w 400 127.0.0.1 >nul
goto wait_loop

:run_game
rem --- здесь Steam подставляет команду запуска игры ---
%*
endlocal
