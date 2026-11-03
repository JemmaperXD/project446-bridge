@echo off
chcp 65001 >nul
rem ============================================================
rem  Project 446 — разовая настройка Windows.
rem
rem  Добавляет в hosts строку:  127.0.0.1 gc.project446.com
rem  Если старая версия приклеила запись к последней строке
rem  (в файле не было перевода строки в конце) — исправляет это.
rem  Права администратора запросит сам (окно UAC -> "Да").
rem ============================================================
setlocal EnableExtensions

set "HOSTS=%SystemRoot%\System32\drivers\etc\hosts"
set "FIX=%~dp0fix_hosts.ps1"

net session >nul 2>&1
if errorlevel 1 (
    echo Сейчас появится окно UAC — нажмите "Да".
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

if not exist "%FIX%" (
    echo.
    echo  [project446] ОШИБКА: рядом нет fix_hosts.ps1.
    echo  [project446] Распакуйте архив ЦЕЛИКОМ, не по одному файлу.
    echo.
    pause
    exit /b 1
)

rem Бэкап делаем один раз, до любых изменений.
if not exist "%HOSTS%.project446.bak" (
    copy /y "%HOSTS%" "%HOSTS%.project446.bak" >nul
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%FIX%"
set "RC=%ERRORLEVEL%"

if "%RC%"=="10" (
    echo [project446] Запись в hosts уже есть — всё готово.
    goto done
)
if "%RC%"=="0" (
    echo [project446] Готово: 127.0.0.1 gc.project446.com добавлено в hosts.
    goto done
)

echo.
echo  [project446] ОШИБКА: не удалось изменить hosts (код %RC%).
echo  [project446] Откройте Блокнотом от администратора:
echo      %HOSTS%
echo  [project446] и добавьте строку:  127.0.0.1 gc.project446.com
echo.

:done
echo.
echo  Теперь можно играть. Steam сам запустит мост.
echo.
pause
