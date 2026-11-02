@echo off
chcp 65001 >nul
rem ============================================================
rem  Project 446 — разовая настройка Windows.
rem
rem  Добавляет в hosts строку:  127.0.0.1 gc.project446.com
rem  Права администратора запросит сам (окно UAC -> "Да").
rem
rem  Запускать один раз. Для отмены см. README.md ("Как всё убрать").
rem ============================================================
setlocal

net session >nul 2>&1
if errorlevel 1 (
    echo Сейчас появится окно UAC — нажмите "Да".
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

findstr /I /C:"gc.project446.com" "%SystemRoot%\System32\drivers\etc\hosts" >nul 2>&1
if not errorlevel 1 (
    echo [project446] Запись в hosts уже есть — всё готово.
    goto done
)

rem Бэкап hosts на всякий случай (не перезаписываем существующий).
if not exist "%SystemRoot%\System32\drivers\etc\hosts.project446.bak" (
    copy /y "%SystemRoot%\System32\drivers\etc\hosts" "%SystemRoot%\System32\drivers\etc\hosts.project446.bak" >nul
)

>>"%SystemRoot%\System32\drivers\etc\hosts" echo 127.0.0.1 gc.project446.com
echo [project446] Готово: 127.0.0.1 gc.project446.com добавлено в hosts.

:done
echo.
echo  Теперь можно играть. Steam сам запустит мост.
echo.
pause
