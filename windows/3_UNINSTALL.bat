@echo off
chcp 65001 >nul
rem ============================================================
rem  Project 446 — удаление моста (Windows).
rem
rem  Убирает из hosts запись 127.0.0.1 gc.project446.com.
rem  По желанию удаляет и саму папку с мостом.
rem  Игру и Steam это НЕ удаляет.
rem
rem  Запускать, только если мост больше не нужен.
rem ============================================================
setlocal EnableExtensions

for %%I in ("%~dp0.") do set "BRIDGE_DIR=%%~fI"
set "HOSTS=%SystemRoot%\System32\drivers\etc\hosts"
set "REMOVE=%~dp0remove_hosts.ps1"

net session >nul 2>&1
if errorlevel 1 (
    echo Сейчас появится окно UAC — нажмите "Да".
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo  Это удалит мост Project 446:
echo    - запись 127.0.0.1 gc.project446.com из hosts
echo    - по желанию папку с программой
echo.
echo  Игра и Steam останутся на месте.
echo.
choice /C YN /N /M "Продолжить? [Y/N]: "
if errorlevel 2 goto cancel

if not exist "%REMOVE%" (
    echo.
    echo  [project446] ОШИБКА: рядом нет remove_hosts.ps1.
    echo  [project446] Распакуйте архив ЦЕЛИКОМ, не по одному файлу.
    echo.
    pause
    exit /b 1
)

rem Бэкап hosts — на случай, если что-то пойдёт не так.
if not exist "%HOSTS%.project446.bak" (
    copy /y "%HOSTS%" "%HOSTS%.project446.bak" >nul
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%REMOVE%"
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
    echo [project446] Запись 127.0.0.1 gc.project446.com удалена из hosts.
) else if "%RC%"=="10" (
    echo [project446] В hosts не было нашей записи — пропускаю.
) else (
    echo.
    echo  [project446] Не удалось изменить hosts (код %RC%).
    echo  [project446] Уберите строку вручную:
    echo      127.0.0.1 gc.project446.com
    echo  [project446] Файл: %HOSTS%
    echo.
)

echo.
echo  Не забудьте убрать параметры запуска в Steam:
echo    Библиотека -^> CS:GO Legacy -^> Свойства -^> Параметры запуска
echo    удалить строку, где есть start_bridge.bat
echo.

rem Останавливаем мост, если он запущен именно из этой папки,
rem иначе папку не получится удалить.
powershell -NoProfile -Command "$d='%BRIDGE_DIR%'; Get-CimInstance Win32_Process -Filter \"Name='pythonw.exe'\" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($d, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }" >nul 2>&1

rem Удаляем папку только если это действительно папка с мостом.
if not exist "%BRIDGE_DIR%\bridge.py" goto no_folder_delete
if not exist "%BRIDGE_DIR%\start_bridge.bat" goto no_folder_delete

echo  Перед удалением закройте игру и чёрное окно Project 446.
echo.
choice /C YN /N /M "Удалить папку с мостом (%BRIDGE_DIR%)? [Y/N]: "
if errorlevel 2 goto done

rem Удаляем папку после выхода из этого скрипта: отдельный cmd подождёт.
> "%TEMP%\project446_remove.cmd" echo @echo off
>>"%TEMP%\project446_remove.cmd" echo cd /d "%TEMP%"
>>"%TEMP%\project446_remove.cmd" echo ping -n 3 127.0.0.1 ^>nul
>>"%TEMP%\project446_remove.cmd" echo rmdir /s /q "%BRIDGE_DIR%"
>>"%TEMP%\project446_remove.cmd" echo del /f /q "%%~f0"
echo.
echo  Папка будет удалена через пару секунд. Окно сейчас закроется.
start "" /min cmd /d /c "%TEMP%\project446_remove.cmd"
exit /b

:no_folder_delete
echo  Папку не трогаю: рядом нет bridge.py или start_bridge.bat.
goto done

:done
echo.
echo  Готово.
echo.
pause
exit /b 0

:cancel
echo.
echo  Отменено, ничего не изменено.
echo.
pause
exit /b 0
